const ffmpeg = require('fluent-ffmpeg');
const multer = require('multer');
const path = require('path');
const fs = require('fs').promises;
const crypto = require('crypto');

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

// Store active streams for processing
const activeStreams = new Map();

/**
 * Start RTMP stream with watermark overlay to YouTube
 */
const startStreamWithWatermark = async (req, res) => {
  try {
    const { rtmpInput, rtmpOutput, watermarkConfig } = req.body;
    
    if (!rtmpInput || !rtmpOutput) {
      return res.status(400).json({ error: 'RTMP input and output URLs required' });
    }

    const streamId = crypto.randomUUID();
    
    // Create FFmpeg command for RTMP relay with watermark
    const command = ffmpeg(rtmpInput)
      .inputOptions([
        '-re', // Read input at native frame rate
        '-i', rtmpInput
      ]);

    // Add watermark if provided
    if (watermarkConfig && watermarkConfig.enabled && watermarkConfig.path) {
      const watermarkPath = path.join(__dirname, '../uploads/watermarks', watermarkConfig.path);
      
      try {
        await fs.access(watermarkPath);
        
        command
          .input(watermarkPath)
          .complexFilter([
            `[1:v]scale=iw:ih,format=rgba,colorchannelmixer=aa=${watermarkConfig.opacity || 0.3}[wm]`,
            '[0:v][wm]overlay=(W-w)/2:(H-h)/2:enable=always[out]'
          ])
          .map('[out]')
          .map('0:a?'); // Map audio if available
      } catch (error) {
        console.warn('Watermark file not found, streaming without watermark:', error.message);
      }
    }

    // Configure output for YouTube RTMP
    command
      .outputOptions([
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-tune', 'zerolatency',
        '-crf', '23',
        '-maxrate', '2500k',
        '-bufsize', '5000k',
        '-pix_fmt', 'yuv420p',
        '-g', '60',
        '-c:a', 'aac',
        '-b:a', '128k',
        '-ar', '44100',
        '-f', 'flv'
      ])
      .output(rtmpOutput);

    // Start the stream
    command.on('start', (commandLine) => {
      console.log(`Started FFmpeg stream ${streamId}:`, commandLine);
      activeStreams.set(streamId, { command, startTime: new Date() });
    });

    command.on('error', (err) => {
      console.error(`FFmpeg stream ${streamId} error:`, err);
      activeStreams.delete(streamId);
    });

    command.on('end', () => {
      console.log(`FFmpeg stream ${streamId} ended`);
      activeStreams.delete(streamId);
    });

    command.run();

    res.json({
      success: true,
      streamId: streamId,
      message: 'Stream started with watermark processing'
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
    const { streamId } = req.body;
    
    if (!streamId) {
      return res.status(400).json({ error: 'Stream ID required' });
    }

    const stream = activeStreams.get(streamId);
    if (!stream) {
      return res.status(404).json({ error: 'Stream not found' });
    }

    // Kill the FFmpeg process
    stream.command.kill('SIGTERM');
    activeStreams.delete(streamId);

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
    const { streamId, rtmpInput } = req.body;
    
    if (!rtmpInput) {
      return res.status(400).json({ error: 'RTMP input URL required' });
    }

    const snapshotId = crypto.randomUUID();
    const snapshotDir = path.join(__dirname, '../uploads/snapshots');
    await fs.mkdir(snapshotDir, { recursive: true });
    
    const snapshotPath = path.join(snapshotDir, `${snapshotId}.jpg`);

    // Capture snapshot using FFmpeg
    ffmpeg(rtmpInput)
      .inputOptions(['-re'])
      .outputOptions([
        '-frames:v', '1',
        '-q:v', '2'
      ])
      .output(snapshotPath)
      .on('end', () => {
        res.json({
          success: true,
          snapshotId: snapshotId,
          snapshotPath: `/snapshots/${snapshotId}.jpg`,
          message: 'Snapshot captured successfully'
        });
      })
      .on('error', (err) => {
        console.error('Snapshot capture error:', err);
        res.status(500).json({
          error: 'Failed to capture snapshot',
          details: err.message
        });
      })
      .run();

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
    const { streamId, rtmpInput, recordingConfig } = req.body;
    
    if (!rtmpInput) {
      return res.status(400).json({ error: 'RTMP input URL required' });
    }

    const recordingId = crypto.randomUUID();
    const recordingDir = path.join(__dirname, '../uploads/recordings');
    await fs.mkdir(recordingDir, { recursive: true });
    
    const recordingPath = path.join(recordingDir, `${recordingId}.mp4`);

    // Start recording using FFmpeg
    const command = ffmpeg(rtmpInput)
      .inputOptions(['-re'])
      .outputOptions([
        '-c:v', 'libx264',
        '-preset', 'fast',
        '-crf', '18',
        '-c:a', 'aac',
        '-b:a', '128k'
      ])
      .output(recordingPath);

    command.on('start', (commandLine) => {
      console.log(`Started recording ${recordingId}:`, commandLine);
      activeStreams.set(`recording_${recordingId}`, { 
        command, 
        startTime: new Date(),
        type: 'recording',
        path: recordingPath
      });
    });

    command.on('error', (err) => {
      console.error(`Recording ${recordingId} error:`, err);
      activeStreams.delete(`recording_${recordingId}`);
    });

    command.on('end', () => {
      console.log(`Recording ${recordingId} ended`);
      activeStreams.delete(`recording_${recordingId}`);
    });

    command.run();

    res.json({
      success: true,
      recordingId: recordingId,
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
    const { recordingId } = req.body;
    
    if (!recordingId) {
      return res.status(400).json({ error: 'Recording ID required' });
    }

    const streamKey = `recording_${recordingId}`;
    const recording = activeStreams.get(streamKey);
    
    if (!recording) {
      return res.status(404).json({ error: 'Recording not found' });
    }

    // Stop the recording
    recording.command.kill('SIGTERM');
    
    const recordingPath = recording.path;
    activeStreams.delete(streamKey);

    // Check if file exists and get stats
    try {
      const stats = await fs.stat(recordingPath);
      res.json({
        success: true,
        recordingId: recordingId,
        recordingPath: `/recordings/${recordingId}.mp4`,
        fileSize: stats.size,
        duration: Math.floor((new Date() - recording.startTime) / 1000),
        message: 'Recording stopped successfully'
      });
    } catch (error) {
      res.json({
        success: true,
        recordingId: recordingId,
        message: 'Recording stopped but file info unavailable'
      });
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
    const activeStreamsList = Array.from(activeStreams.entries()).map(([id, stream]) => ({
      id: id,
      type: stream.type || 'stream',
      startTime: stream.startTime,
      uptime: Math.floor((new Date() - stream.startTime) / 1000)
    }));

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