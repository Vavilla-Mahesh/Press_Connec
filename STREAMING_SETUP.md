# Live Streaming Setup Guide

## Backend Configuration

1. Copy the configuration template:
   ```bash
   cd backend
   cp local.config.json.template local.config.json
   ```

2. Update `local.config.json` with your actual values:
   - Replace `YOUR_GOOGLE_CLIENT_ID` with your Google OAuth client ID
   - Replace `YOUR_GOOGLE_CLIENT_SECRET` with your Google OAuth client secret
   - Change `CHANGE_THIS_PASSWORD` to a secure password
   - Change `CHANGE_THIS_JWT_SECRET_KEY` to a secure random string

3. Ensure your Google OAuth application has YouTube Live Streaming enabled and the redirect URI configured.

## Flutter App Configuration

1. Update `press_connect/assets/config.json`:
   - Set `backendBaseUrl` to your backend server URL
   - Set `googleClientId` to match your OAuth configuration

## Starting the Application

1. Start the backend server:
   ```bash
   cd backend
   npm install
   npm start
   ```

2. The backend will run on http://localhost:5000

3. Run the Flutter app:
   ```bash
   cd press_connect
   flutter pub get
   flutter run
   ```

## Live Streaming Process

1. **Authentication**: Sign in with your YouTube account that has live streaming enabled
2. **Create Stream**: Tap "Go Live" to create a YouTube Live broadcast and RTMP stream
3. **Camera Setup**: The app will request camera and microphone permissions
4. **Start Streaming**: The app connects your camera feed to YouTube's RTMP endpoint
5. **Monitor Stream**: Check your YouTube Live dashboard for the live stream

## Stream Quality Settings

The app supports multiple quality presets:
- **Low**: 640x480, 15fps, 800kbps
- **Medium**: 854x480, 30fps, 1500kbps
- **High**: 1280x720, 30fps, 2500kbps (default)
- **Ultra**: 1920x1080, 30fps, 4000kbps

## Troubleshooting

- Ensure YouTube Live Streaming is enabled for your account
- Check camera and microphone permissions
- Verify network connectivity and bandwidth
- Monitor backend logs for authentication or API errors