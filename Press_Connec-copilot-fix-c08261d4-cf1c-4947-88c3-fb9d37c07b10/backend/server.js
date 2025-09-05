const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');

const authController = require('./src/auth.controller');
const liveController = require('./src/live.controller');

dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;

// Load configuration
let config;
try {
  const configPath = path.join(__dirname, 'local.config.json');
  config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  config.backendBaseUrl = process.env.BACKEND_BASE_URL;
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

// Add these routes to your server.js file after the existing live streaming routes

// Enhanced live streaming routes
app.post('/live/create', verifyToken, liveController.createLiveStream);
app.post('/live/check-and-go-live', verifyToken, liveController.checkAndGoLiveEnhanced); // Use enhanced version
app.get('/live/status/:broadcastId', verifyToken, liveController.getBroadcastStatus); // New route
app.post('/live/end', verifyToken, liveController.endLiveStream);
app.post('/live/transition', verifyToken, liveController.transitionBroadcast);

// Fallback route for minimal stream creation if needed
app.post('/live/create-minimal', verifyToken, liveController.createLiveStreamMinimal);
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
  console.log('Available endpoints:');
  console.log('  POST /auth/app-login');
  console.log('  POST /auth/exchange');
  console.log('  POST /live/create');
  console.log('  POST /live/check-and-go-live');
  console.log('  POST /live/end');
  console.log('  POST /live/transition');
});