const NodeMediaServer = require('node-media-server');
const ffmpeg = require('fluent-ffmpeg');
const path = require('path');
const fs = require('fs').promises;

class RTMPServer {
  constructor() {
    this.mediaServer = null;
    this.activeStreams = new Map();
    this.streamConfigs = new Map();
  }

  /**
   * Initialize RTMP server
   */
  init(config = {}) {
    const rtmpConfig = {
      logType: process.env.NODE_ENV === 'development' ? 3 : 1,
      rtmp: {
        port: config.rtmpPort || 1935,
        chunk_size: 60000,
        gop_cache: true,
        ping: 30,
        ping_timeout: 60
      },
      http: {
        port: config.httpPort || 8000,
        mediaroot: './media',
        allow_origin: '*'
      }
    };

    this.mediaServer = new NodeMediaServer(rtmpConfig);

    // Set up event handlers
    this.mediaServer.on('preConnect', (id, args) => {
      console.log('[NodeEvent on preConnect]', `id=${id} args=${JSON.stringify(args)}`);
    });

    this.mediaServer.on('postConnect', (id, args) => {
      console.log('[NodeEvent on postConnect]', `id=${id} args=${JSON.stringify(args)}`);
    });

    this.mediaServer.on('doneConnect', (id, args) => {
      console.log('[NodeEvent on doneConnect]', `id=${id} args=${JSON.stringify(args)}`);
    });

    this.mediaServer.on('prePublish', (id, StreamPath, args) => {
      console.log('[NodeEvent on prePublish]', `id=${id} StreamPath=${StreamPath} args=${JSON.stringify(args)}`);
      
      // Extract stream key from path (e.g., /live/streamkey)
      const streamKey = StreamPath.split('/').pop();
      
      // Check if we have configuration for this stream
      if (this.streamConfigs.has(streamKey)) {
        const config = this.streamConfigs.get(streamKey);
        this.startStreamRelay(id, StreamPath, config);
      }
    });

    this.mediaServer.on('postPublish', (id, StreamPath, args) => {
      console.log('[NodeEvent on postPublish]', `id=${id} StreamPath=${StreamPath} args=${JSON.stringify(args)}`);
    });

    this.mediaServer.on('donePublish', (id, StreamPath, args) => {
      console.log('[NodeEvent on donePublish]', `id=${id} StreamPath=${StreamPath} args=${JSON.stringify(args)}`);
      
      const streamKey = StreamPath.split('/').pop();
      this.stopStreamRelay(streamKey);
    });
  }

  /**
   * Start the RTMP server
   */
  start() {
    if (this.mediaServer) {
      this.mediaServer.run();
      console.log('RTMP Server started on port 1935');
      console.log('HTTP Server started on port 8000');
    }
  }

  /**
   * Stop the RTMP server
   */
  stop() {
    if (this.mediaServer) {
      this.mediaServer.stop();
      console.log('RTMP Server stopped');
    }
  }

  /**
   * Configure a stream for processing and relay
   */
  configureStream(streamKey, config) {
    this.streamConfigs.set(streamKey, config);
    console.log(`Stream ${streamKey} configured:`, config);
  }

  /**
   * Remove stream configuration
   */
  removeStreamConfig(streamKey) {
    this.streamConfigs.delete(streamKey);
    this.stopStreamRelay(streamKey);
  }

  /**
   * Start relaying stream with watermark to YouTube
   */
  startStreamRelay(sessionId, streamPath, config) {
    const streamKey = streamPath.split('/').pop();
    
    if (this.activeStreams.has(streamKey)) {
      console.log(`Stream ${streamKey} already being relayed`);
      return;
    }

    const inputUrl = `rtmp://localhost:1935${streamPath}`;
    const outputUrl = config.youtubeRtmpUrl;

    console.log(`Starting relay: ${inputUrl} -> ${outputUrl}`);

    // Create FFmpeg command for processing and relay
    const command = ffmpeg(inputUrl)
      .inputOptions([
        '-re', // Read input at native frame rate
      ]);

    // Add watermark if configured
    if (config.watermark && config.watermark.enabled && config.watermark.path) {
      const watermarkPath = path.join(__dirname, '../uploads/watermarks', config.watermark.path);
      
      // Check if watermark file exists
      fs.access(watermarkPath)
        .then(() => {
          command
            .input(watermarkPath)
            .complexFilter([
              `[1:v]scale=iw:ih,format=rgba,colorchannelmixer=aa=${config.watermark.opacity || 0.3}[wm]`,
              '[0:v][wm]overlay=(W-w)/2:(H-h)/2:enable=always[out]'
            ])
            .map('[out]')
            .map('0:a?'); // Map audio if available
        })
        .catch((error) => {
          console.warn(`Watermark file not found: ${watermarkPath}, streaming without watermark`);
        });
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
      .output(outputUrl);

    // Set up event handlers
    command.on('start', (commandLine) => {
      console.log(`FFmpeg relay started for ${streamKey}:`, commandLine);
      this.activeStreams.set(streamKey, {
        command,
        sessionId,
        config,
        startTime: new Date()
      });
    });

    command.on('error', (err) => {
      console.error(`FFmpeg relay error for ${streamKey}:`, err);
      this.activeStreams.delete(streamKey);
    });

    command.on('end', () => {
      console.log(`FFmpeg relay ended for ${streamKey}`);
      this.activeStreams.delete(streamKey);
    });

    // Start the relay
    command.run();
  }

  /**
   * Stop relaying a specific stream
   */
  stopStreamRelay(streamKey) {
    const stream = this.activeStreams.get(streamKey);
    if (stream) {
      try {
        stream.command.kill('SIGTERM');
        this.activeStreams.delete(streamKey);
        console.log(`Stream relay stopped for ${streamKey}`);
      } catch (error) {
        console.error(`Error stopping stream relay for ${streamKey}:`, error);
      }
    }
  }

  /**
   * Capture snapshot from stream
   */
  async captureSnapshot(streamKey, outputPath) {
    const inputUrl = `rtmp://localhost:1935/live/${streamKey}`;
    
    return new Promise((resolve, reject) => {
      ffmpeg(inputUrl)
        .inputOptions(['-re'])
        .outputOptions([
          '-frames:v', '1',
          '-q:v', '2'
        ])
        .output(outputPath)
        .on('end', () => {
          console.log(`Snapshot captured for ${streamKey}: ${outputPath}`);
          resolve(outputPath);
        })
        .on('error', (err) => {
          console.error(`Snapshot capture error for ${streamKey}:`, err);
          reject(err);
        })
        .run();
    });
  }

  /**
   * Start recording stream
   */
  startRecording(streamKey, outputPath, config = {}) {
    const inputUrl = `rtmp://localhost:1935/live/${streamKey}`;
    const recordingKey = `recording_${streamKey}`;
    
    if (this.activeStreams.has(recordingKey)) {
      throw new Error('Recording already in progress for this stream');
    }

    const command = ffmpeg(inputUrl)
      .inputOptions(['-re'])
      .outputOptions([
        '-c:v', config.videoCodec || 'libx264',
        '-preset', config.preset || 'fast',
        '-crf', config.crf || '18',
        '-c:a', config.audioCodec || 'aac',
        '-b:a', config.audioBitrate || '128k'
      ])
      .output(outputPath);

    command.on('start', (commandLine) => {
      console.log(`Recording started for ${streamKey}:`, commandLine);
      this.activeStreams.set(recordingKey, {
        command,
        type: 'recording',
        streamKey,
        outputPath,
        startTime: new Date()
      });
    });

    command.on('error', (err) => {
      console.error(`Recording error for ${streamKey}:`, err);
      this.activeStreams.delete(recordingKey);
    });

    command.on('end', () => {
      console.log(`Recording ended for ${streamKey}`);
      this.activeStreams.delete(recordingKey);
    });

    command.run();
    return recordingKey;
  }

  /**
   * Stop recording
   */
  stopRecording(streamKey) {
    const recordingKey = `recording_${streamKey}`;
    const recording = this.activeStreams.get(recordingKey);
    
    if (recording) {
      recording.command.kill('SIGTERM');
      this.activeStreams.delete(recordingKey);
      return {
        outputPath: recording.outputPath,
        duration: Math.floor((new Date() - recording.startTime) / 1000)
      };
    }
    return null;
  }

  /**
   * Get active streams info
   */
  getActiveStreams() {
    const streams = [];
    for (const [key, stream] of this.activeStreams.entries()) {
      streams.push({
        key,
        type: stream.type || 'relay',
        startTime: stream.startTime,
        uptime: Math.floor((new Date() - stream.startTime) / 1000)
      });
    }
    return streams;
  }
}

module.exports = RTMPServer;