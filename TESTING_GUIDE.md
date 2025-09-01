# Live Streaming Test Scenarios

## Manual Testing Guide

### Prerequisites
1. YouTube account with live streaming enabled
2. Valid Google OAuth credentials configured
3. Mobile device with camera permissions
4. Backend server running

### Test Scenario 1: Basic Live Stream Creation
1. **Start Backend**: `cd backend && npm start`
2. **Launch App**: Open Flutter app on device/emulator
3. **Login**: Use valid credentials to login
4. **Connect YouTube**: Complete OAuth flow for YouTube
5. **Navigate to Go Live**: Should see camera preview
6. **Verify Watermark**: Default watermark should be visible in preview
7. **Click "Go Live"**: 
   - Should see "Preparing..." status
   - Should create YouTube live broadcast
   - Should transition to "Broadcasting" status
   - Should show "LIVE" indicator
   - Should show RTMP streaming status

### Test Scenario 2: Watermark Configuration
1. **Access Settings**: Click settings icon in Go Live screen
2. **Toggle Watermark**: Enable/disable watermark overlay
3. **Adjust Opacity**: Use slider to change watermark opacity
4. **Verify Preview**: Changes should be visible in camera preview
5. **Start Stream**: Watermark should be included in actual stream

### Test Scenario 3: Stream Management
1. **Start Streaming**: Follow Scenario 1
2. **Monitor Status**: Verify streaming indicators are accurate
3. **Stop Stream**: Click "Stop Live" button
   - Should show "Stopping..." status
   - Should end YouTube broadcast
   - Should return to idle state
4. **Error Handling**: Simulate network issues, verify error messages

### Expected YouTube Live Stream Features
- **Video Quality**: 1280x720 at 30fps
- **Bitrate**: 2.5 Mbps video, 128kbps audio
- **Watermark**: Positioned in top-right with configurable opacity
- **Auto-Start**: Stream begins immediately after "Go Live"
- **Status Sync**: YouTube broadcast status matches app state

### Backend API Testing
```bash
# Health check
curl http://localhost:5000/health

# Create live stream (requires auth token)
curl -X POST http://localhost:5000/live/create \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json"

# Transition broadcast
curl -X POST http://localhost:5000/live/transition \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"broadcastId": "<id>", "broadcastStatus": "live"}'

# End stream
curl -X POST http://localhost:5000/live/end \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"broadcastId": "<id>"}'
```

### Troubleshooting
- **Camera Issues**: Check device permissions
- **YouTube Auth**: Verify OAuth credentials and scopes
- **Streaming Fails**: Check network connectivity and RTMP URL
- **Watermark Missing**: Ensure asset exists and permissions are correct
- **Backend Errors**: Check server logs and configuration

### Success Criteria
✅ Live stream appears in YouTube channel  
✅ Video quality matches configuration  
✅ Watermark is visible on stream  
✅ Audio is synchronized  
✅ Stream starts automatically after "Go Live"  
✅ Status indicators are accurate  
✅ Error handling works correctly  