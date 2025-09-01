# YouTube Live Stream Fix Documentation

## Problem
The application was experiencing "Stream is inactive" errors when trying to transition YouTube live broadcasts to "live" status. This happened because the code attempted to transition broadcasts immediately after creation, without waiting for actual video data to be sent to the RTMP endpoint.

## Root Cause
YouTube's Live API requires that actual video data is being streamed to the RTMP endpoint before a broadcast can be transitioned from "ready" to "live" status. The previous implementation:

1. Created a broadcast (status: "ready")
2. Created a stream
3. Bound them together
4. **Immediately** tried to transition to "live" (❌ This fails if no video data is flowing)

## Solution
The fix implements a robust transition system with:

### 1. Retry Logic with Exponential Backoff
- Attempts transition up to 3 times
- Progressive delays: 5 seconds → 20 seconds → 60 seconds
- Only retries on "Stream is inactive" errors

### 2. Stream Status Checking
- Verifies broadcast status before attempting transitions
- Checks if stream is already live to avoid duplicate transitions
- New `/live/status` endpoint for monitoring stream health

### 3. Better Error Handling
- Specific error messages for different failure scenarios
- User-friendly explanations about RTMP streaming requirements
- Proper HTTP status codes

### 4. Improved User Experience
- Clear instructions when stream is inactive
- Detailed status information via the status endpoint
- Graceful handling of edge cases

## API Endpoints

### Enhanced Endpoints
- `POST /live/transition` - Now includes retry logic and better error handling
- `POST /live/end` - Improved validation and error messages

### New Endpoint
- `GET /live/status?broadcastId=<id>` - Check broadcast and stream health

## Usage Flow
1. Create broadcast: `POST /live/create`
2. Start streaming video to the provided RTMP URL using streaming software
3. Check status: `GET /live/status?broadcastId=<id>` (optional)
4. Go live: `POST /live/transition` with `broadcastStatus: "live"`
5. End stream: `POST /live/end`

## Error Messages
The system now provides clear error messages:

- **"Stream is inactive"**: User needs to start streaming video to RTMP endpoint
- **"Invalid transition"**: Broadcast is not in a valid state for the requested transition
- **"Broadcast not found"**: Invalid broadcast ID provided

## Configuration
Copy `backend/local.config.json.example` to `backend/local.config.json` and configure with your actual YouTube API credentials.