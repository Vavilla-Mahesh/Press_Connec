const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');

const authController = require('./src/auth.controller');
const liveController = require('./src/live.controller');
const adminController = require('./src/admin.controller');
const database = require('./src/database');
const userManager = require('./src/user.manager');
const tokenStore = require('./src/token.store');
const googleOAuth = require('./src/google.oauth');

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
    appLogin: localConfig.appLogin,
    oauth: {
      clientId: process.env.GOOGLE_CLIENT_ID || localConfig.oauth.clientId,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET || localConfig.oauth.clientSecret || null,
      redirectUri: localConfig.oauth.redirectUri
    },
    jwt: {
      secret: process.env.JWT_SECRET || localConfig.jwt.secret,
      expiresIn: localConfig.jwt.expiresIn
    },
    database: {
      host: process.env.DB_HOST || localConfig.database.host,
      port: process.env.DB_PORT || localConfig.database.port,
      database: process.env.DB_NAME || localConfig.database.database,
      user: process.env.DB_USER || localConfig.database.user,
      password: process.env.DB_PASSWORD || localConfig.database.password,
      ssl: process.env.DB_SSL === 'true' || localConfig.database.ssl
    },
    encryption: {
      key: process.env.ENCRYPTION_KEY || localConfig.encryption.key
    },
    backendBaseUrl: process.env.BACKEND_BASE_URL
  };
  
  console.log('Configuration loaded successfully');
  console.log(`OAuth Client ID: ${config.oauth.clientId}`);
  console.log(`OAuth Client Secret: ${config.oauth.clientSecret ? '[CONFIGURED]' : '[NOT CONFIGURED - Android OAuth Mode]'}`);
} catch (error) {
  console.error('Failed to load configuration:', error);
  process.exit(1);
}

// Initialize database and users
const initializeApp = async () => {
  try {
    // Initialize database connection and schema
    await database.initializeDatabase(config);
    
    // Initialize users from config
    await userManager.initializeUsers(config);
    
    // Start token refresh system (runs every 5 minutes)
    setInterval(async () => {
      try {
        await tokenStore.refreshExpiredTokens(config.encryption.key, config.oauth, googleOAuth);
      } catch (error) {
        console.error('Token refresh system error:', error);
      }
    }, 5 * 60 * 1000);
    
    console.log('Application initialized successfully');
  } catch (error) {
    console.error('Failed to initialize application:', error);
    process.exit(1);
  }
};

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

// Admin middleware - only allow admin users (those without associatedWith)
const verifyAdmin = async (req, res, next) => {
  // First verify the token
  await new Promise((resolve, reject) => {
    verifyToken(req, res, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });

  // Check if user is admin (no associatedWith)
  if (req.user.associatedWith) {
    return res.status(403).json({ error: 'Admin access required' });
  }

  next();
};
const verifyToken = async (req, res, next) => {
  const token = req.headers.authorization?.replace('Bearer ', '');

  if (!token) {
    return res.status(401).json({ error: 'No token provided' });
  }

  try {
    const decoded = jwt.verify(token, config.jwt.secret);
    
    // Validate session if sessionId is present
    if (decoded.sessionId) {
      const session = await userManager.validateSession(decoded.sessionId);
      if (!session) {
        return res.status(401).json({ error: 'Session expired or invalid' });
      }
      
      // Update user info with session data
      req.user = {
        ...decoded,
        associatedWith: session.associatedWith
      };
    } else {
      req.user = decoded;
    }
    
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
};

// Routes
app.post('/auth/app-login', authController.appLogin);
app.post('/auth/validate-session', authController.validateSession);
app.post('/auth/logout', verifyToken, authController.logout);
app.post('/auth/exchange', verifyToken, authController.exchangeCode);

// Admin routes
app.post('/admin/users', verifyAdmin, adminController.createUser);
app.get('/admin/users', verifyAdmin, adminController.getUsers);
app.put('/admin/users/:username', verifyAdmin, adminController.updateUser);
app.delete('/admin/users/:username', verifyAdmin, adminController.deleteUser);
app.get('/admin/stats', verifyAdmin, adminController.getUserStats);

// Enhanced live streaming routes
app.post('/live/create', verifyToken, liveController.createLiveStream);
app.post('/live/end', verifyToken, liveController.endLiveStream);
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

// Initialize app and start server
(async () => {
  await initializeApp();
  
  app.listen(PORT, () => {
    console.log(`Press Connect Backend running on port ${PORT}`);
    console.log(`Health check: http://localhost:${PORT}/health`);
    console.log('Available endpoints:');
    console.log('  POST /auth/app-login');
    console.log('  POST /auth/validate-session');
    console.log('  POST /auth/logout');
    console.log('  POST /auth/exchange');
    console.log('  POST /admin/users (admin only)');
    console.log('  GET  /admin/users (admin only)');
    console.log('  PUT  /admin/users/:username (admin only)');
    console.log('  DELETE /admin/users/:username (admin only)');
    console.log('  GET  /admin/stats (admin only)');
    console.log('  POST /live/create');
    console.log('  POST /live/end');
  });
})();