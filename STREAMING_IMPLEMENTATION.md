# YouTube Live Streaming Setup Guide

## 🚀 Quick Start

### 1. Backend Setup

```bash
cd backend
npm install
cp local.config.json.template local.config.json
# Edit local.config.json with your credentials
node server.js
```

The backend will start:
- **HTTP Server**: `http://localhost:5000` 
- **RTMP Server**: `rtmp://localhost:1935`
- **HTTP Media Server**: `http://localhost:8000`

### 2. Flutter App Setup

```bash
cd press_connect
flutter pub get
flutter run
```

## 🔧 Configuration

### Backend Configuration (`backend/local.config.json`)

```json
{
  "appLogin": [
    {
      "username": "admin",
      "password": "YOUR_SECURE_PASSWORD"
    }
  ],
  "oauth": {
    "clientId": "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com",
    "redirectUri": "com.example.press_connect:/oauth2redirect"
  },
  "jwt": {
    "secret": "your-super-secret-jwt-key-min-32-characters"
  }
}
```

### Flutter Configuration (`press_connect/assets/config.json`)

```json
{
  "backendBaseUrl": "http://localhost:5000",
  "googleClientId": "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com",
  "youtubeScopes": [
    "https://www.googleapis.com/auth/youtube",
    "https://www.googleapis.com/auth/youtube.force-ssl"
  ],
  "defaultWatermarkOpacity": 0.3
}
```

## 🎥 How It Works

### Streaming Architecture

```
[Mobile App] --RTMP--> [Backend RTMP Server] --RTMP--> [YouTube]
                              ↓
                        [FFmpeg Processing]
                              ↓
                     [Watermarks, Snapshots, Recording]
```

### Stream Flow

1. **Create Live Stream**: App calls backend to create YouTube broadcast
2. **Start Streaming**: Backend configures RTMP relay with watermark processing
3. **Mobile Streams**: App streams to `rtmp://backend:1935/live/{streamKey}`
4. **Processing**: Backend applies watermarks and relays to YouTube
5. **Live on YouTube**: Processed stream appears on YouTube Live
6. **Features**: Snapshots and recordings available during stream

## 📱 Using the App

### 1. Authentication
- Launch app and login with backend credentials
- Connect YouTube account via OAuth

### 2. Go Live
- Tap "Go Live" 
- Grant camera/microphone permissions
- Configure watermark settings
- Tap "Go Live" button

### 3. During Stream
- **Snapshot**: Tap camera icon to capture frame
- **Recording**: Tap record button to start/stop recording
- **Stop**: Tap "Stop Live" to end stream

## 🔧 Features

### ✅ Live Streaming
- Direct RTMP streaming to YouTube
- Real-time video transmission
- Automatic stream quality optimization

### ✅ Server-Side Watermarks
- PNG watermark support with transparency
- Configurable opacity (0-100%)
- Applied before YouTube transmission
- No client-side processing overhead

### ✅ Snapshots
- Capture frames during live streaming
- Saved on backend server (not mobile gallery)
- Accessible via API endpoints
- Real-time processing

### ✅ Recording
- Record streams to MP4 files
- Backend storage (not mobile device)
- Configurable quality settings
- Start/stop during live streaming

### ✅ Stream Management
- Reliable start/stop functionality
- Proper YouTube broadcast transitions
- Resource cleanup and error handling
- Stream status monitoring

## 🛠️ API Endpoints

### Authentication
- `POST /auth/app-login` - App authentication
- `POST /auth/exchange` - YouTube OAuth exchange

### Live Streaming
- `POST /live/create` - Create YouTube broadcast
- `POST /live/transition` - Transition broadcast status
- `POST /live/end` - End live broadcast

### Stream Processing
- `POST /streaming/start` - Configure RTMP processing
- `POST /streaming/stop` - Stop RTMP processing
- `POST /streaming/snapshot` - Capture snapshot
- `POST /streaming/recording/start` - Start recording
- `POST /streaming/recording/stop` - Stop recording

### Resources
- `GET /snapshots/{id}.jpg` - Download snapshot
- `GET /recordings/{id}.mp4` - Download recording
- `GET /streaming/status` - Get active streams

## 📦 Dependencies

### Backend
- **express**: HTTP server
- **node-media-server**: RTMP server
- **fluent-ffmpeg**: Video processing
- **googleapis**: YouTube API
- **multer**: File uploads

### Flutter
- **rtmp_broadcaster**: RTMP streaming
- **camera**: Camera access
- **provider**: State management
- **dio**: HTTP client

## 🐛 Troubleshooting

### Common Issues

1. **RTMP Connection Failed**
   - Check backend is running on port 1935
   - Verify network connectivity
   - Check firewall settings

2. **YouTube Authentication**
   - Verify Google Client ID
   - Check OAuth redirect URI
   - Ensure YouTube Live is enabled

3. **Watermark Not Appearing**
   - Upload watermark image via API
   - Check watermark path configuration
   - Verify image format (PNG recommended)

4. **Stream Quality Issues**
   - Adjust bitrate settings
   - Check network bandwidth
   - Monitor backend resources

### Debug Commands

```bash
# Check backend health
curl http://localhost:5000/health

# Monitor RTMP streams
curl http://localhost:5000/streaming/status

# View backend logs
node server.js

# Test FFmpeg
ffmpeg -version
```

## 🔒 Security Notes

- Change default passwords in production
- Use HTTPS for production deployments
- Secure JWT secrets (32+ characters)
- Configure firewall for RTMP port
- Use environment variables for sensitive data

## 📈 Production Deployment

### Environment Variables

```bash
export APP_USERNAME=your_admin_username
export APP_PASSWORD=your_secure_password
export GOOGLE_CLIENT_ID=your_client_id
export JWT_SECRET=your_jwt_secret
export PORT=5000
export RTMP_PORT=1935
```

### Docker Support

```dockerfile
FROM node:18
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 5000 1935 8000
CMD ["node", "server.js"]
```

This implementation provides a complete, production-ready YouTube Live streaming solution with all requested features including server-side watermarks, snapshots, and recording capabilities.