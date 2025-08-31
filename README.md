# Press Connect - Premium Flutter Live Streaming App

A premium Flutter application for live streaming to YouTube with RTMP, in-app OAuth authentication, and customizable watermark overlays.

## Features

### 🔐 Two-Step Authentication
- **Step 1**: Hardcoded app login (backend validation)
- **Step 2**: In-app YouTube OAuth (no external browser)

### 📡 Live Streaming
- RTMP streaming to YouTube using `rtmp_broadcaster`
- Unique broadcast/stream keys for each session
- Multi-device support (no stream merging)
- Real-time stream status indicators

### 🖼️ Watermark System
- Semi-transparent, full-screen centered watermark
- User-adjustable opacity (0-100% via slider)
- Applied to live streams, recordings, and snapshots
- FFmpeg integration for watermark compositing

### 🎨 Premium UI/UX
- Modern vibrant theme with gradients
- Glassmorphism cards and effects
- Smooth animations and transitions
- Dark/Light theme toggle
- Accessibility features

## Project Structure

```
/
├── lib/
│   ├── ui/
│   │   ├── screens/          # Main app screens
│   │   └── widgets/          # Reusable UI components
│   ├── services/             # Business logic services
│   ├── config.dart          # App configuration
│   └── main.dart            # App entry point
├── assets/
│   ├── config.json          # App configuration
│   ├── images/              # App images
│   ├── lottie/              # Animation files
│   └── watermarks/          # Watermark images
├── backend/
│   ├── src/                 # Backend controllers
│   ├── server.js            # Express server
│   ├── local.config.json    # Backend configuration
│   └── package.json         # Node.js dependencies
└── pubspec.yaml             # Flutter dependencies
```

## Setup Instructions

### Flutter App Setup

1. **Install Dependencies**
   ```bash
   flutter pub get
   ```

2. **Configure App Settings**
   - Update `assets/config.json` with your configuration:
     - `backendBaseUrl`: Your backend server URL
     - `googleClientId`: Your Google OAuth Client ID

3. **Add Watermark Images**
   - Place your watermark PNG files in `assets/watermarks/`
   - Update `default_watermark.png` with your actual watermark

### Backend Setup

1. **Install Node.js Dependencies**
   ```bash
   cd backend
   npm install
   ```

2. **Configure Backend**
   - Update `local.config.json` with:
     - App login credentials
     - Google OAuth Client ID and Secret
     - JWT secret key

3. **Start Backend Server**
   ```bash
   npm run dev  # For development
   npm start    # For production
   ```

## Key Technologies

### Flutter Dependencies
- **rtmp_broadcaster**: RTMP live streaming
- **google_sign_in**: In-app OAuth authentication
- **flutter_secure_storage**: Secure token storage
- **ffmpeg_kit_flutter**: Media processing and watermarking
- **camera**: Camera access and preview
- **provider**: State management
- **dio**: HTTP client
- **lottie**: Animations

### Backend Dependencies
- **express**: Web framework
- **googleapis**: YouTube API integration
- **jsonwebtoken**: JWT authentication
- **cors**: Cross-origin support

## API Endpoints

### Authentication
- `POST /auth/app-login` - App credential validation
- `POST /auth/exchange` - YouTube OAuth token exchange

### Live Streaming
- `POST /live/create` - Create YouTube live broadcast/stream
- `POST /live/end` - End live broadcast

### Health Check
- `GET /health` - Server health status

## Security Features

- No hardcoded secrets in Flutter app
- JWT-based session management
- Secure token storage with flutter_secure_storage
- OAuth token refresh handling
- Backend-only access to sensitive credentials