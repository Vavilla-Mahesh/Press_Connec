# Live Streaming Implementation

## Overview
This implementation provides real-time video streaming to YouTube Live with watermark overlay support. The solution uses FFmpeg for RTMP streaming and integrates with YouTube's Live Streaming API.

## Architecture

### Frontend (Flutter)
- **LiveService**: Manages overall live streaming workflow
- **RTMPStreamingService**: Handles actual video streaming using FFmpeg
- **WatermarkService**: Manages watermark configuration and overlay
- **GoLiveScreen**: User interface for live streaming controls

### Backend (Node.js)
- **live.controller.js**: YouTube API integration for broadcast management
- **OAuth integration**: Handles YouTube authentication and token refresh
- **RTMP endpoints**: Creates streams and manages broadcast lifecycle

## Key Features

### ✅ Automatic Stream Start
- Creates YouTube live broadcast
- Starts RTMP streaming automatically
- Transitions broadcast to "live" status
- No manual intervention required

### ✅ Watermark Overlay
- Configurable opacity (0-100%)
- Positioned in top-right corner
- Applied directly to video stream
- Asset loading from Flutter assets

### ✅ Production Quality
- 1280x720 resolution at 30fps
- 2.5 Mbps video bitrate
- 128kbps audio bitrate
- H.264 encoding with AAC audio

### ✅ Real-time Status
- Live streaming indicators
- RTMP connection status
- Error handling and recovery
- Stream state management

## Technical Implementation

### RTMP Streaming
```dart
// Uses FFmpeg for cross-platform streaming
String ffmpegCommand = [
  '-f', 'avfoundation',  // iOS camera input
  '-i', '0:0',           // Video:Audio
  '-i', watermarkPath,   // Watermark overlay
  '-filter_complex', 'watermark_filter',
  '-c:v', 'libx264',     // H.264 encoding
  '-b:v', '2500k',       // 2.5 Mbps bitrate
  '-f', 'flv',           // FLV format for RTMP
  rtmpUrl                // YouTube RTMP endpoint
].join(' ');
```

### Watermark Filter
```dart
// FFmpeg filter for watermark overlay
String watermarkFilter = 
  '[1:v]scale=200:200,format=rgba,colorchannelmixer=aa=$opacity[wm];'
  '[0:v][wm]overlay=W-w-20:20:enable=always';
```

### YouTube API Integration
```javascript
// Create live broadcast
const broadcast = await youtube.liveBroadcasts.insert({
  part: ['snippet', 'status'],
  requestBody: {
    snippet: {
      title: 'Press Connect Live',
      scheduledStartTime: new Date().toISOString()
    },
    status: { privacyStatus: 'public' }
  }
});

// Create RTMP stream
const stream = await youtube.liveStreams.insert({
  part: ['snippet', 'cdn'],
  requestBody: {
    cdn: {
      frameRate: '30fps',
      ingestionType: 'rtmp',
      resolution: '720p'
    }
  }
});

// Bind broadcast to stream
await youtube.liveBroadcasts.bind({
  id: broadcast.id,
  streamId: stream.id
});
```

## Configuration

### Flutter App Config
```json
{
  "backendBaseUrl": "https://your-backend.com",
  "streaming": {
    "defaultBitrate": 2500,
    "defaultResolution": {
      "width": 1280,
      "height": 720
    }
  },
  "watermark": {
    "defaultImagePath": "assets/watermarks/default_watermark.png",
    "maxOpacity": 1.0,
    "minOpacity": 0.0
  }
}
```

### Backend Config
```json
{
  "oauth": {
    "clientId": "your-google-client-id",
    "clientSecret": "your-google-client-secret",
    "scopes": [
      "https://www.googleapis.com/auth/youtube",
      "https://www.googleapis.com/auth/youtube.upload"
    ]
  }
}
```

## API Endpoints

### POST /live/create
Creates YouTube live broadcast and returns RTMP details.

**Response:**
```json
{
  "success": true,
  "broadcastId": "youtube-broadcast-id",
  "streamId": "youtube-stream-id", 
  "ingestUrl": "rtmp://a.rtmp.youtube.com/live2",
  "streamKey": "your-stream-key"
}
```

### POST /live/transition
Transitions broadcast status (testing → live → complete).

**Request:**
```json
{
  "broadcastId": "youtube-broadcast-id",
  "broadcastStatus": "live"
}
```

### POST /live/end
Ends the live broadcast.

**Request:**
```json
{
  "broadcastId": "youtube-broadcast-id"
}
```

## Error Handling

### Common Issues
1. **Camera Permission**: Handled in app initialization
2. **YouTube Auth**: Token refresh mechanism implemented
3. **Network Issues**: Retry logic and user feedback
4. **RTMP Connection**: FFmpeg error handling and recovery
5. **Asset Loading**: Watermark fallback handling

### Debug Information
- Console logs for streaming status
- FFmpeg output monitoring
- API error response handling
- User-friendly error messages

## Testing

### Unit Tests
- Service initialization
- State management
- Error handling
- Configuration validation

### Integration Tests
- End-to-end streaming flow
- YouTube API integration
- Watermark overlay verification
- Multi-platform compatibility

### Manual Testing
- See TESTING_GUIDE.md for detailed scenarios
- Covers all user workflows
- Includes troubleshooting steps

## Performance Considerations

### Optimization
- Efficient FFmpeg parameters
- Minimal UI re-renders
- Proper resource cleanup
- Memory management

### Scalability
- Stateless backend design
- JWT-based authentication
- Configurable streaming parameters
- Platform-specific optimizations

## Security

### Data Protection
- Secure token storage
- HTTPS-only communication
- OAuth 2.0 implementation
- No sensitive data logging

### Permissions
- Camera/microphone access
- Network permissions
- Storage permissions for temp files
- YouTube account authorization

## Future Enhancements

### Potential Improvements
- Multiple watermark positions
- Custom streaming qualities
- Stream recording capability
- Advanced error recovery
- Analytics and monitoring
- Multi-camera support
- Real-time chat integration

This implementation provides a solid foundation for live streaming with room for expansion based on specific requirements.