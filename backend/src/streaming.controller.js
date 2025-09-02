const ffmpeg = require('fluent-ffmpeg');
const multer = require('multer');
const path = require('path');
const fs = require('fs').promises;
const crypto = require('crypto');
const RTMPServer = require('./rtmp.server');

// Initialize RTMP server
const rtmpServer = new RTMPServer();
rtmpServer.init({
  rtmpPort: process.env.RTMP_PORT || 1935,
  httpPort: process.env.RTMP_HTTP_PORT || 8000
});

// Start RTMP server
rtmpServer.start();

// Configure multer for watermark uploads
const storage = multer.diskStorage({
  destination: async (req, file, cb) => {
    const uploadDir = path.join(__dirname, '../uploads/watermarks');
    try {
      await fs.mkdir(uploadDir, { recursive: true });
      cb(null, uploadDir);
    } catch (error) {
      cb(error);
    }
  },
  filename: (req, file, cb) => {
    const uniqueName = `${crypto.randomUUID()}-${file.originalname}`;
    cb(null, uniqueName);
  }
});

const upload = multer({
  storage: storage,
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Only image files allowed'), false);
    }
  },
  limits: {
    fileSize: 5 * 1024 * 1024 // 5MB limit
  }
});

/**
 * Start RTMP stream with watermark overlay to YouTube
 */
const startStreamWithWatermark = async (req, res) => {
  try {
    const { youtubeRtmpUrl, watermarkConfig } = req.body;
    
    if (!youtubeRtmpUrl) {
      return res.status(400).json({ error: 'YouTube RTMP URL required' });
    }

    // Generate unique stream key
    const streamKey = crypto.randomUUID();
    
    // Configure the stream in RTMP server
    rtmpServer.configureStream(streamKey, {
      youtubeRtmpUrl: youtubeRtmpUrl,
      watermark: watermarkConfig || { enabled: false }
    });

    // Return the RTMP endpoint for the mobile app to stream to
    const rtmpEndpoint = `rtmp://localhost:1935/live/${streamKey}`;

    res.json({
      success: true,
      streamKey: streamKey,
      rtmpEndpoint: rtmpEndpoint,
      message: 'RTMP stream configured successfully'
    });

  } catch (error) {
    console.error('Start stream error:', error);
    res.status(500).json({
      error: 'Failed to start stream',
      details: error.message
    });
  }
};

/**
 * Stop RTMP stream
 */
const stopStream = async (req, res) => {
  try {
    const { streamKey } = req.body;
    
    if (!streamKey) {
      return res.status(400).json({ error: 'Stream key required' });
    }

    // Remove stream configuration and stop relay
    rtmpServer.removeStreamConfig(streamKey);

    res.json({
      success: true,
      message: 'Stream stopped successfully'
    });

  } catch (error) {
    console.error('Stop stream error:', error);
    res.status(500).json({
      error: 'Failed to stop stream',
      details: error.message
    });
  }
};

/**
 * Capture snapshot from active stream
 */
const captureSnapshot = async (req, res) => {
  try {
    const { streamKey } = req.body;
    
    if (!streamKey) {
      return res.status(400).json({ error: 'Stream key required' });
    }

    const snapshotId = crypto.randomUUID();
    const snapshotDir = path.join(__dirname, '../uploads/snapshots');
    await fs.mkdir(snapshotDir, { recursive: true });
    
    const snapshotPath = path.join(snapshotDir, `${snapshotId}.jpg`);

    // Capture snapshot using RTMP server
    await rtmpServer.captureSnapshot(streamKey, snapshotPath);

    res.json({
      success: true,
      snapshotId: snapshotId,
      snapshotPath: `/snapshots/${snapshotId}.jpg`,
      message: 'Snapshot captured successfully'
    });

  } catch (error) {
    console.error('Capture snapshot error:', error);
    res.status(500).json({
      error: 'Failed to capture snapshot',
      details: error.message
    });
  }
};

/**
 * Start recording stream to file
 */
const startRecording = async (req, res) => {
  try {
    const { streamKey, recordingConfig } = req.body;
    
    if (!streamKey) {
      return res.status(400).json({ error: 'Stream key required' });
    }

    const recordingId = crypto.randomUUID();
    const recordingDir = path.join(__dirname, '../uploads/recordings');
    await fs.mkdir(recordingDir, { recursive: true });
    
    const recordingPath = path.join(recordingDir, `${recordingId}.mp4`);

    // Start recording using RTMP server
    const recordingKey = rtmpServer.startRecording(streamKey, recordingPath, recordingConfig || {});

    res.json({
      success: true,
      recordingId: recordingId,
      recordingKey: recordingKey,
      recordingPath: `/recordings/${recordingId}.mp4`,
      message: 'Recording started successfully'
    });

  } catch (error) {
    console.error('Start recording error:', error);
    res.status(500).json({
      error: 'Failed to start recording',
      details: error.message
    });
  }
};

/**
 * Stop recording
 */
const stopRecording = async (req, res) => {
  try {
    const { streamKey, recordingId } = req.body;
    
    if (!streamKey) {
      return res.status(400).json({ error: 'Stream key required' });
    }

    // Stop recording using RTMP server
    const recordingResult = rtmpServer.stopRecording(streamKey);
    
    if (recordingResult) {
      // Check if file exists and get stats
      try {
        const stats = await fs.stat(recordingResult.outputPath);
        res.json({
          success: true,
          recordingId: recordingId,
          recordingPath: `/recordings/${path.basename(recordingResult.outputPath)}`,
          fileSize: stats.size,
          duration: recordingResult.duration,
          message: 'Recording stopped successfully'
        });
      } catch (error) {
        res.json({
          success: true,
          recordingId: recordingId,
          duration: recordingResult.duration,
          message: 'Recording stopped successfully'
        });
      }
    } else {
      res.status(404).json({ error: 'No active recording found for this stream' });
    }

  } catch (error) {
    console.error('Stop recording error:', error);
    res.status(500).json({
      error: 'Failed to stop recording',
      details: error.message
    });
  }
};

/**
 * Upload watermark image
 */
const uploadWatermark = upload.single('watermark');

/**
 * Get list of available watermarks
 */
const getWatermarks = async (req, res) => {
  try {
    const watermarkDir = path.join(__dirname, '../uploads/watermarks');
    
    try {
      const files = await fs.readdir(watermarkDir);
      const watermarks = files
        .filter(file => /\.(png|jpg|jpeg)$/i.test(file))
        .map(file => ({
          filename: file,
          path: `/watermarks/${file}`,
          uploadDate: new Date().toISOString() // In real app, get actual file stats
        }));

      res.json({
        success: true,
        watermarks: watermarks
      });
    } catch (error) {
      // Directory doesn't exist yet
      res.json({
        success: true,
        watermarks: []
      });
    }

  } catch (error) {
    console.error('Get watermarks error:', error);
    res.status(500).json({
      error: 'Failed to get watermarks',
      details: error.message
    });
  }
};

/**
 * Get stream status
 */
const getStreamStatus = async (req, res) => {
  try {
    const activeStreamsList = rtmpServer.getActiveStreams();

    res.json({
      success: true,
      activeStreams: activeStreamsList,
      totalStreams: activeStreamsList.length
    });

  } catch (error) {
    console.error('Get stream status error:', error);
    res.status(500).json({
      error: 'Failed to get stream status',
      details: error.message
    });
  }
};

module.exports = {
  startStreamWithWatermark,
  stopStream,
  captureSnapshot,
  startRecording,
  stopRecording,
  uploadWatermark,
  getWatermarks,
  getStreamStatus
};