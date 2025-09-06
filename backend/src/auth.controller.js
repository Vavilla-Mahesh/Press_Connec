const jwt = require('jsonwebtoken');
const googleOAuth = require('./google.oauth');
const tokenStore = require('./token.store');
const userManager = require('./user.manager');

const appLogin = async (req, res) => {
  try {
    const { username, password } = req.body;
    
    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password required' });
    }

    // Validate credentials against database
    const validUser = await userManager.validateUserCredentials(username, password);

    if (!validUser) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Create session in PostgreSQL
    const session = await userManager.createUserSession(validUser.username);

    // Generate JWT token with session ID
    const token = jwt.sign(
      { 
        username: validUser.username,
        sessionId: session.sessionId,
        associatedWith: validUser.associatedWith
      },
      req.config.jwt.secret,
      { expiresIn: req.config.jwt.expiresIn }
    );

    res.json({
      success: true,
      token,
      user: { 
        username: validUser.username,
        associatedWith: validUser.associatedWith
      },
      session: {
        sessionId: session.sessionId,
        expiresAt: session.expiresAt
      }
    });

  } catch (error) {
    console.error('App login error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

const exchangeCode = async (req, res) => {
  try {
    const { serverAuthCode } = req.body;
    
    if (!serverAuthCode) {
      return res.status(400).json({ error: 'Server auth code required' });
    }

    // Exchange server auth code for tokens
    const tokens = await googleOAuth.exchangeCodeForTokens(
      serverAuthCode,
      req.config.oauth
    );

    if (!tokens) {
      return res.status(400).json({ error: 'Failed to exchange auth code' });
    }

    // Store tokens for this user (encrypted in PostgreSQL)
    await tokenStore.storeTokens(req.user.username, tokens, req.config.encryption.key);

    res.json({
      success: true,
      message: 'YouTube authentication successful'
    });

  } catch (error) {
    console.error('Code exchange error:', error);
    res.status(500).json({ error: 'Failed to exchange auth code' });
  }
};

const validateSession = async (req, res) => {
  try {
    const { sessionId } = req.body;
    
    if (!sessionId) {
      return res.status(400).json({ error: 'Session ID required' });
    }

    const session = await userManager.validateSession(sessionId);
    
    if (!session) {
      return res.status(401).json({ 
        valid: false, 
        error: 'Invalid or expired session' 
      });
    }

    // Check if user has YouTube tokens (directly or through association)
    const tokens = await tokenStore.getTokens(session.username, req.config.encryption.key);
    
    res.json({
      valid: true,
      user: {
        username: session.username,
        associatedWith: session.associatedWith
      },
      hasYouTubeAuth: !!tokens,
      requiresYouTubeAuth: !tokens && !session.associatedWith
    });

  } catch (error) {
    console.error('Session validation error:', error);
    res.status(500).json({ error: 'Session validation failed' });
  }
};

const logout = async (req, res) => {
  try {
    const sessionId = req.user.sessionId;
    
    if (sessionId) {
      await userManager.deactivateSession(sessionId);
    }

    res.json({
      success: true,
      message: 'Logged out successfully'
    });

  } catch (error) {
    console.error('Logout error:', error);
    res.status(500).json({ error: 'Logout failed' });
  }
};

module.exports = {
  appLogin,
  exchangeCode,
  validateSession,
  logout
};