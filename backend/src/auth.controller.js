const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const googleOAuth = require('./google.oauth');
const tokenStore = require('./token.store');

const appLogin = async (req, res) => {
  try {
    const { username, password } = req.body;
    
    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password required' });
    }

    // Check credentials against config
    const validUser = req.config.appLogin.find(user => 
      user.username === username && user.password === password
    );

    if (!validUser) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Generate JWT token
    const token = jwt.sign(
      { username: validUser.username },
      req.config.jwt.secret,
      { expiresIn: '7d' } // 7 days expiration
    );

    res.json({
      success: true,
      token,
      user: { username: validUser.username }
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

    // Store tokens for this user
    await tokenStore.storeTokens(req.user.username, tokens);

    res.json({
      success: true,
      message: 'YouTube authentication successful'
    });

  } catch (error) {
    console.error('Code exchange error:', error);
    res.status(500).json({ error: 'Failed to exchange auth code' });
  }
};

module.exports = {
  appLogin,
  exchangeCode
};