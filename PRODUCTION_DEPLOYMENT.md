# Production Deployment Guide

This guide covers deploying the enhanced Press Connect app with all production features implemented.

## New Production Features

### 1. Stream Analytics Integration ✅
- **Backend**: YouTube Analytics API integration via `/analytics/stream` and `/analytics/live` endpoints
- **Frontend**: `AnalyticsService` for real-time stream metrics and historical data
- **Features**: 
  - Real-time viewer count, chat messages
  - Historical analytics (views, watch time, engagement)
  - Performance metrics and insights

### 2. Enhanced Error Recovery ✅
- **Circuit Breaker Pattern**: Prevents cascade failures across services
- **Exponential Backoff**: Smart retry mechanisms for API calls
- **Service-Specific Recovery**: Different strategies for YouTube API, analytics, and streaming
- **Auto-Recovery**: Automatic reconnection and quality adjustment

### 3. Performance Optimizations ✅
- **Adaptive Streaming**: Automatic quality adjustment based on network conditions
- **Performance Monitoring**: Real-time frame rate, dropped frames, and bandwidth monitoring
- **Memory Management**: Optimized camera handling and resource cleanup
- **Network Adaptation**: Dynamic bitrate adjustment

### 4. Native RTMP Implementation 🔄
- **Platform Channels**: Ready for iOS/Android native RTMP integration
- **Unified Interface**: Single API for all platforms via `NativeRTMPChannel`
- **Event Streaming**: Real-time native events for connection status and performance
- **Quality Control**: Dynamic quality adjustment during streaming

## Backend Deployment

### Environment Variables

Set these in your production environment:

```bash
# Authentication
APP_USERNAME=your_admin_username
APP_PASSWORD=your_secure_password
JWT_SECRET=your_jwt_secret_256_bit

# Google/YouTube API
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret

# Database (if using external storage)
DATABASE_URL=your_database_url

# Monitoring
NODE_ENV=production
LOG_LEVEL=info
```

### Deployment Options

#### Option 1: Heroku

```bash
# Deploy backend
cd backend
heroku create press-connect-backend
heroku config:set APP_USERNAME=admin
heroku config:set APP_PASSWORD=your_secure_password
heroku config:set JWT_SECRET=your_jwt_secret
heroku config:set GOOGLE_CLIENT_ID=your_google_client_id
heroku config:set GOOGLE_CLIENT_SECRET=your_google_client_secret
git push heroku main
```

#### Option 2: AWS/DigitalOcean

```bash
# Install dependencies
npm install

# Use PM2 for process management
npm install -g pm2

# Create ecosystem file
cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'press-connect-backend',
    script: 'server.js',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 5000
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true
  }]
};
EOF

# Start with PM2
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

### Nginx Configuration

```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Increased timeouts for streaming
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

### SSL Setup

```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx

# Get SSL certificate
sudo certbot --nginx -d your-domain.com

# Auto-renewal
sudo crontab -e
# Add: 0 12 * * * /usr/bin/certbot renew --quiet
```

## Flutter App Deployment

### Configuration

Update `assets/config.json` for production:

```json
{
  "backendBaseUrl": "https://your-domain.com",
  "googleClientId": "your_google_client_id.apps.googleusercontent.com",
  "redirectUri": "https://your-domain.com/auth/callback",
  "features": {
    "analytics": true,
    "adaptiveStreaming": true,
    "nativeRTMP": true,
    "errorRecovery": true
  }
}
```

### Build Commands

#### Android

```bash
# Release build
flutter build appbundle --release --build-name=1.0.0 --build-number=1

# APK (if needed)
flutter build apk --release --build-name=1.0.0 --build-number=1
```

#### iOS

```bash
# Release build
flutter build ios --release --build-name=1.0.0 --build-number=1

# Archive for App Store
xcodebuild -workspace ios/Runner.xcworkspace \
           -scheme Runner \
           -configuration Release \
           -archivePath build/Runner.xcarchive \
           archive
```

#### Web

```bash
# Web deployment
flutter build web --release --web-renderer html

# Deploy to your web server
cp -r build/web/* /var/www/your-domain/
```

## Native RTMP Setup

### iOS Setup

1. **Add Dependencies** to `ios/Podfile`:
```ruby
pod 'HaishinKit', '~> 1.4.0'
```

2. **Implement Native Code**: Follow the [Native RTMP Implementation Guide](./NATIVE_RTMP_IMPLEMENTATION.md)

3. **Configure Permissions** in `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for live streaming</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for live streaming</string>
```

### Android Setup

1. **Add Dependencies** to `android/app/build.gradle`:
```gradle
implementation 'com.github.pedroSG94.rtmp-rtsp-stream-client-java:rtmpandcamera:2.2.3'
```

2. **Implement Native Code**: Follow the [Native RTMP Implementation Guide](./NATIVE_RTMP_IMPLEMENTATION.md)

3. **Configure Permissions** in `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

## Monitoring & Analytics

### Backend Monitoring

Add monitoring endpoints:

```javascript
// Add to server.js
app.get('/metrics', (req, res) => {
  res.json({
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    circuitBreakers: {
      youtube: circuitBreakers.youtube.getState(),
      analytics: circuitBreakers.analytics.getState(),
      streaming: circuitBreakers.streaming.getState()
    },
    timestamp: new Date().toISOString()
  });
});
```

### Error Tracking

Integrate error tracking services:

```javascript
// Backend: Add Sentry or similar
const Sentry = require('@sentry/node');

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV
});

// Flutter: Add Crashlytics or Sentry
```

### Performance Monitoring

Configure performance tracking:

```dart
// Flutter app monitoring
class PerformanceMonitor {
  static void trackStreamingSession(Duration duration, String quality) {
    // Track to Firebase Analytics, Mixpanel, etc.
  }
  
  static void trackError(String error, Map<String, dynamic> context) {
    // Track errors and context
  }
}
```

## Security Configuration

### Backend Security

1. **Rate Limiting**:
```javascript
const rateLimit = require('express-rate-limit');

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});

app.use(limiter);
```

2. **CORS Configuration**:
```javascript
const corsOptions = {
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
  optionsSuccessStatus: 200
};

app.use(cors(corsOptions));
```

3. **Security Headers**:
```javascript
const helmet = require('helmet');
app.use(helmet());
```

### App Security

1. **Certificate Pinning** (for critical APIs)
2. **Token Encryption** (secure storage)
3. **API Key Protection** (obfuscation)

## Testing in Production

### Backend Health Checks

```bash
# Health endpoint
curl https://your-domain.com/health

# Metrics endpoint
curl https://your-domain.com/metrics

# Analytics endpoints (with auth)
curl -H "Authorization: Bearer YOUR_TOKEN" \
     "https://your-domain.com/analytics/live?broadcastId=BROADCAST_ID"
```

### App Testing

1. **Different Network Conditions**: Test 2G, 3G, 4G, WiFi
2. **Quality Adaptation**: Verify automatic quality adjustment
3. **Error Recovery**: Test network disconnections and reconnections
4. **Analytics**: Verify real-time metrics and historical data
5. **Native RTMP**: Test platform-specific streaming

### Load Testing

```bash
# Install artillery
npm install -g artillery

# Create test config
cat > load-test.yml << EOF
config:
  target: 'https://your-domain.com'
  phases:
    - duration: 60
      arrivalRate: 10
scenarios:
  - name: "Health check"
    requests:
      - get:
          url: "/health"
EOF

# Run load test
artillery run load-test.yml
```

## Scaling Considerations

### Database
- Use PostgreSQL or MongoDB for analytics data
- Implement caching with Redis for frequent queries
- Consider read replicas for analytics queries

### CDN
- Use CloudFlare or AWS CloudFront for static assets
- Cache API responses where appropriate

### Auto-scaling
- Configure horizontal pod autoscaling (Kubernetes)
- Use load balancers for multiple backend instances

## Backup & Recovery

### Database Backups
```bash
# Automated backups
0 2 * * * pg_dump -h localhost -U user database > backup_$(date +%Y%m%d).sql
```

### Configuration Backups
- Store environment variables in secure key management
- Version control configuration files
- Backup SSL certificates

## Maintenance

### Updates
1. **Backend**: Use blue-green deployment for zero downtime
2. **Mobile App**: Implement in-app update notifications
3. **Dependencies**: Regular security updates

### Monitoring
1. **Uptime Monitoring**: Use services like Pingdom or UptimeRobot
2. **Performance**: Monitor response times and error rates
3. **Business Metrics**: Track streaming success rates, user engagement

This production deployment guide ensures your enhanced Press Connect app runs reliably at scale with all the new features working optimally.