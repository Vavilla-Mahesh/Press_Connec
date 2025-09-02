
const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');

const authController = require('./src/auth.controller');
const liveController = require('./src/live.controller');
const streamingController = require('./src/streaming.controller');

dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;


// Load configuration
let config;
try {
  const configPath = path.join(__dirname, 'local.config.json');
  const localConfig = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  
  // Merge local config with environment variables
  config = {
    appLogin: [
      { 
        username: process.env.APP_USERNAME || localConfig.appLogin[0].username,
        password: process.env.APP_PASSWORD || localConfig.appLogin[0].password
      }
    ],
    oauth: {
      clientId: process.env.GOOGLE_CLIENT_ID || localConfig.oauth.clientId,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET || localConfig.oauth.clientSecret || null,
      redirectUri: localConfig.oauth.redirectUri
    },
    jwt: {
      secret: process.env.JWT_SECRET || localConfig.jwt.secret
    }
  };
} catch (error) {
  console.error('Failed to load configuration:', error);
  process.exit(1);
}

// Middleware
app.use(cors());
app.use(express.json());

// Request logging
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
  next();
});

// Make config available to controllers
app.use((req, res, next) => {
  req.config = config;
  next();
});

// JWT verification middleware
const verifyToken = (req, res, next) => {
  const token = req.headers.authorization?.replace('Bearer ', '');

  if (!token) {
    return res.status(401).json({ error: 'No token provided' });
  }

  try {
    const decoded = jwt.verify(token, config.jwt.secret);
    req.user = decoded;
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
};

// Routes
app.post('/auth/app-login', authController.appLogin);
app.post('/auth/exchange', verifyToken, authController.exchangeCode);

app.post('/live/create', verifyToken, liveController.createLiveStream);
app.post('/live/transition', verifyToken, liveController.transitionBroadcast);
app.post('/live/end', verifyToken, liveController.endLiveStream);

// Streaming routes
app.post('/streaming/start', verifyToken, streamingController.startStreamWithWatermark);
app.post('/streaming/stop', verifyToken, streamingController.stopStream);
app.post('/streaming/snapshot', verifyToken, streamingController.captureSnapshot);
app.post('/streaming/recording/start', verifyToken, streamingController.startRecording);
app.post('/streaming/recording/stop', verifyToken, streamingController.stopRecording);
app.post('/streaming/watermark/upload', verifyToken, streamingController.uploadWatermark);
app.get('/streaming/watermarks', verifyToken, streamingController.getWatermarks);
app.get('/streaming/status', verifyToken, streamingController.getStreamStatus);

// Static file serving for uploads
app.use('/snapshots', express.static(path.join(__dirname, 'uploads/snapshots')));
app.use('/recordings', express.static(path.join(__dirname, 'uploads/recordings')));
app.use('/watermarks', express.static(path.join(__dirname, 'uploads/watermarks')));

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// Error handler
app.use((error, req, res, next) => {
  console.error('Server error:', error);
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? error.message : undefined
  });
});

app.listen(PORT, () => {
  console.log(`Press Connect Backend running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
});