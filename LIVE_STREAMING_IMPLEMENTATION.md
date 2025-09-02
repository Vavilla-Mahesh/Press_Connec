# Live Streaming Implementation Notes

## Current Implementation Status

### ✅ Working Features
- YouTube Live broadcast creation via backend API
- RTMP streaming from mobile camera to YouTube
- Live/Test streaming modes
- Start/Stop streaming functionality
- Snapshot capture during streaming
- Recording functionality (local to device)
- Proper error handling and state management

### ⚠️ Known Limitations

#### 1. Watermark Overlay
**Current State**: Watermark is displayed as UI overlay only, not embedded in actual stream.

**Reason**: The `rtmp_broadcaster` package streams camera feed directly to RTMP without compositing UI elements.

**Solutions**:
1. **Server-side Processing (Recommended for Production)**:
   - Set up RTMP relay server with FFmpeg
   - App streams to relay server instead of directly to YouTube
   - Server applies watermark and forwards to YouTube
   - See `backend/src/rtmp.relay.js` for implementation template

2. **Client-side Video Composition**:
   - Replace `rtmp_broadcaster` with a package that supports overlay composition
   - Or implement custom video processing pipeline

#### 2. Recording Location
**Current State**: Recordings are saved to device local storage.

**Production Recommendation**: 
- Stream recording should be handled server-side
- Server can simultaneously record and forward stream
- Eliminates device storage concerns

## Production Implementation Guide

### Server-side Watermark Processing

1. **Setup RTMP Relay Server**:
```bash
# Install FFmpeg on server
apt-get install ffmpeg

# Install Node.js RTMP server
npm install node-media-server
```

2. **Configure FFmpeg Watermark Processing**:
```bash
# Example FFmpeg command for watermark overlay
ffmpeg -i rtmp://localhost:1935/live/INPUT_STREAM \
       -i watermark.png \
       -filter_complex "[0:v][1:v]overlay=W-w-10:H-h-10" \
       -c:v libx264 -c:a aac \
       -f flv rtmp://a.rtmp.youtube.com/live2/YOUTUBE_STREAM_KEY
```

3. **Update App Configuration**:
```dart
// Instead of streaming directly to YouTube
final rtmpUrl = 'rtmp://your-server.com:1935/live/${streamKey}';

// Server will handle forwarding to YouTube with watermark
```

### Backend RTMP Relay Implementation

The `backend/src/rtmp.relay.js` file contains a template for implementing server-side processing. Key components:

1. **RTMP Input Server**: Receives stream from mobile app
2. **FFmpeg Processing**: Applies watermark overlay
3. **RTMP Output**: Forwards processed stream to YouTube
4. **Recording**: Simultaneously save stream file
5. **Monitoring**: Track stream health and quality

### Mobile App Changes Required

1. **Update Stream Target**:
```dart
// Change from direct YouTube streaming
final streamInfo = LiveStreamInfo(
  ingestUrl: 'rtmp://your-server.com:1935/live',
  streamKey: 'app_generated_key',
  broadcastId: youtubeResponse.broadcastId,
);
```

2. **Server Communication**:
```dart
// Notify server of stream start/stop
await dio.post('/live/relay/start', {
  'streamKey': streamKey,
  'youtubeUrl': youtubeIngestUrl,
  'watermarkConfig': watermarkService.getRTMPWatermarkConfig(),
});
```

## Testing the Current Implementation

### Prerequisites
1. YouTube account with live streaming enabled
2. Google OAuth credentials configured
3. Backend server running with valid configuration

### Test Workflow
1. **Start Backend**: `cd backend && npm start`
2. **Configure App**: Update `assets/config.json` with backend URL
3. **Authenticate**: Login and connect YouTube account
4. **Create Stream**: Tap "Go Live" to create YouTube broadcast
5. **Start Streaming**: Stream will begin to YouTube (without watermark)
6. **Test Features**:
   - Take snapshots during streaming
   - Start/stop recording
   - Stop stream gracefully

### Verification
- Check YouTube Live dashboard for active stream
- Verify stream appears on YouTube (may take 10-30 seconds)
- Confirm clean stop ends both RTMP and YouTube broadcast

## Future Enhancements

1. **Quality Selection**: Allow users to choose stream quality presets
2. **Stream Health Monitoring**: Display connection quality and bitrate
3. **Multiple Platform Support**: Extend to Facebook, Twitch, etc.
4. **Advanced Recording**: Cloud recording with automatic upload
5. **Stream Analytics**: Viewer count, duration, quality metrics

## Troubleshooting

### Common Issues
1. **No Video on YouTube**: Check RTMP URL and stream key
2. **Stream Disconnects**: Verify network stability and server capacity
3. **Poor Quality**: Adjust bitrate and resolution settings
4. **Permission Errors**: Ensure camera and microphone permissions granted

### Debug Logs
Enable debug mode in Flutter for detailed streaming logs:
```dart
if (kDebugMode) {
  print('RTMP streaming started successfully');
}
```