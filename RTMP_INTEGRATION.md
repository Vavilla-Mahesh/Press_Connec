# RTMP Integration Guide

## Current Status

The live streaming functionality has been implemented with the following structure:

### ✅ Completed Features

1. **YouTube API Integration**
   - Creates live broadcasts on YouTube
   - Starts and stops broadcasts properly
   - Handles authentication and error cases

2. **Camera Integration**
   - Camera preview working
   - Camera controller properly initialized
   - Camera permissions handled

3. **Snapshot & Recording**
   - Take snapshots and save to gallery
   - Video recording with start/stop functionality
   - Proper permissions for Android 13+ and iOS
   - Gallery saving implementation

4. **Backend API**
   - `/live/create` - Creates YouTube broadcast and stream
   - `/live/start` - Starts the YouTube broadcast
   - `/live/end` - Ends the YouTube broadcast
   - Proper error handling and authentication

### 🚧 RTMP Streaming Implementation Needed

The `rtmp_broadcaster` package integration is partially implemented but needs completion:

#### Current Implementation
- Service structure ready for RTMP integration
- Camera controller connection established
- RTMP URL generation working (`${ingestUrl}/${streamKey}`)

#### Required Steps for Full RTMP Integration

1. **Update rtmp_broadcaster dependency**
   ```yaml
   # In pubspec.yaml, verify the correct package and version
   rtmp_broadcaster: ^2.3.4  # Check latest version
   ```

2. **Implement RTMP streaming in LiveService**
   ```dart
   // Add back the import
   import 'package:rtmp_broadcaster/rtmp_broadcaster.dart';
   
   // Initialize RTMP broadcaster
   _rtmpBroadcaster = RtmpBroadcaster();
   await _rtmpBroadcaster!.initialize(
     url: _currentStream!.rtmpUrl,
     videoBitrate: AppConfig.defaultBitrate,
     videoResolution: Size(
       AppConfig.defaultResolution['width']!.toDouble(),
       AppConfig.defaultResolution['height']!.toDouble(),
     ),
   );
   
   // Start streaming
   await _rtmpBroadcaster!.startStreaming();
   
   // Stop streaming
   await _rtmpBroadcaster!.stopStreaming();
   ```

3. **Camera Feed Integration**
   ```dart
   // Connect camera to RTMP broadcaster
   await _rtmpBroadcaster!.setVideoSource(_cameraController!);
   ```

## Testing the Current Implementation

### Backend Testing
```bash
cd backend
npm start

# Test endpoints
curl -X POST http://localhost:5000/auth/app-login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "1234"}'

# Use returned token for live streaming endpoints
curl -X POST http://localhost:5000/live/create \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Flutter Testing
```bash
cd press_connect
flutter test
```

## Error Resolution

### Issue 1: Video Not Streaming
**Root Cause:** RTMP broadcaster not properly connected to camera feed
**Solution:** Complete the RTMP integration as outlined above

### Issue 2: Stop Live Errors
**Root Cause:** Improved error handling in backend and proper cleanup
**Status:** ✅ FIXED - Better error handling and graceful degradation

### Issue 3: Snapshot/Recording Not Saved
**Root Cause:** Missing gallery integration and permissions
**Status:** ✅ FIXED - Full implementation with proper permissions

## Next Steps

1. **Complete RTMP Integration**
   - Research the exact API for `rtmp_broadcaster:^2.3.4`
   - Implement the missing RTMP streaming code
   - Test with actual YouTube live streams

2. **Add Network Status Monitoring**
   - Monitor RTMP connection status
   - Handle network interruptions gracefully
   - Provide user feedback for connection issues

3. **Enhanced Error Handling**
   - More specific error messages for different failure modes
   - Retry mechanisms for transient failures
   - Better user guidance for setup issues

## Configuration Notes

- YouTube Live streaming must be enabled on the account
- Proper OAuth scopes required (already configured)
- Network connectivity required for both API calls and RTMP streaming
- Camera and microphone permissions required
- Gallery permissions for saving snapshots/recordings