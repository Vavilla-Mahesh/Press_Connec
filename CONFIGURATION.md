# Configuration Guide

This guide helps you configure the Press Connect app for production use.

## Google Cloud Setup

### 1. Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Note your project ID

### 2. Enable YouTube Data API v3

1. Navigate to **APIs & Services > Library**
2. Search for "YouTube Data API v3"
3. Click on it and press **Enable**

### 3. Create OAuth 2.0 Credentials

1. Go to **APIs & Services > Credentials**
2. Click **Create Credentials > OAuth 2.0 Client ID**
3. Configure the application type:
   - **Android**: Add package name and SHA-1 certificate fingerprint
   - **iOS**: Add bundle identifier
4. Download the configuration file

### 4. Get SHA-1 Fingerprint (Android)

For debug builds:
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

For release builds, use your release keystore:
```bash
keytool -list -v -keystore your-release-key.keystore -alias your-key-alias
```

## App Configuration

### 1. Update Flutter Configuration

Edit `assets/config.json`:
```json
{
  "backendBaseUrl": "https://your-backend-domain.com",
  "googleClientId": "YOUR_ACTUAL_CLIENT_ID.apps.googleusercontent.com",
  "youtubeScopes": [
    "openid",
    "email", 
    "profile",
    "https://www.googleapis.com/auth/youtube",
    "https://www.googleapis.com/auth/youtube.readonly",
    "https://www.googleapis.com/auth/youtube.upload"
  ],
  "defaultWatermarkOpacity": 0.3
}
```

### 2. Update Backend Configuration

Edit `backend/local.config.json`:
```json
{
  "appLogin": [
    { "username": "your_admin_username", "password": "your_secure_password" }
  ],
  "oauth": {
    "clientId": "YOUR_ACTUAL_CLIENT_ID.apps.googleusercontent.com",
    "clientSecret": "YOUR_ACTUAL_CLIENT_SECRET",
    "redirectUri": "com.pressconnect.app:/oauth2redirect"
  },
  "jwt": {
    "secret": "your-super-secret-jwt-key-min-32-characters",
    "expiresIn": "24h"
  }
}
```

**⚠️ Security Note**: Never commit actual credentials to version control!

### 3. Add Watermark Images

1. Replace `assets/watermarks/default_watermark.png` with your actual watermark
2. Ensure the image has transparency (PNG format)
3. Recommended size: 1920x1080 or larger for best quality

## Environment Variables (Production)

For production deployment, use environment variables instead of config files:

### Backend Environment Variables
```bash
export APP_USERNAME=your_admin_username
export APP_PASSWORD=your_secure_password
export GOOGLE_CLIENT_ID=your_client_id
export GOOGLE_CLIENT_SECRET=your_client_secret
export JWT_SECRET=your_jwt_secret
export PORT=5000
```

### Modify Backend for Environment Variables

Update `server.js` to read from environment variables when available:
```javascript
const config = {
  appLogin: [
    { 
      username: process.env.APP_USERNAME || localConfig.appLogin[0].username,
      password: process.env.APP_PASSWORD || localConfig.appLogin[0].password
    }
  ],
  oauth: {
    clientId: process.env.GOOGLE_CLIENT_ID || localConfig.oauth.clientId,
    clientSecret: process.env.GOOGLE_CLIENT_SECRET || localConfig.oauth.clientSecret,
    redirectUri: localConfig.oauth.redirectUri
  },
  jwt: {
    secret: process.env.JWT_SECRET || localConfig.jwt.secret,
    expiresIn: localConfig.jwt.expiresIn
  }
};
```

## Testing Configuration

### 1. Test Backend Endpoints

Health check:
```bash
curl http://localhost:5000/health
```

App login:
```bash
curl -X POST http://localhost:5000/auth/app-login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "1234"}'
```

### 2. Test YouTube API Access

Ensure your YouTube account has:
- YouTube Live enabled
- Proper channel setup
- Streaming permissions

### 3. Test OAuth Flow

1. Run the Flutter app
2. Complete login flow
3. Verify OAuth redirect works
4. Check backend logs for token exchange

## Troubleshooting

### Common Issues

1. **OAuth Error "redirect_uri_mismatch"**
   - Verify redirect URI in Google Cloud Console matches exactly
   - Check bundle ID/package name

2. **YouTube Live Not Available**
   - Enable YouTube Live in YouTube Studio
   - Verify account has no live streaming restrictions

3. **Camera Permission Denied**
   - Check app permissions in device settings
   - Verify manifest permissions are correct

4. **Backend Connection Failed**
   - Check network connectivity
   - Verify backend URL in app config
   - Ensure backend server is running

### Debug Logs

Enable debug logging in Flutter:
```dart
import 'package:flutter/foundation.dart';

if (kDebugMode) {
  print('Debug message: $variable');
}
```

Backend logs:
```bash
# View backend console output
node server.js

# Or with detailed logging
DEBUG=* node server.js
```

## Production Deployment

### Backend Deployment Options

1. **Heroku**
   ```bash
   heroku create your-app-name
   heroku config:set GOOGLE_CLIENT_ID=your_id
   heroku config:set GOOGLE_CLIENT_SECRET=your_secret
   git push heroku main
   ```

2. **AWS/DigitalOcean/VPS**
   - Set up Node.js environment
   - Configure environment variables
   - Use PM2 for process management
   - Set up SSL/HTTPS

### Flutter App Deployment

1. **Android**
   ```bash
   flutter build apk --release
   # or
   flutter build appbundle --release
   ```

2. **iOS**
   ```bash
   flutter build ios --release
   ```

Remember to update the backend URL in production builds!