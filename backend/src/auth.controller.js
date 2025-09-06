const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const googleOAuth = require('./google.oauth');
const tokenStore = require('./token.store.enhanced');
const userService = require('./user.service');
const database = require('./database');

const appLogin = async (req, res) => {
  try {
    const { username, password } = req.body;
    
    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password required' });
    }

    let user = null;

    // Try database authentication first
    if (database.isAvailable()) {
      user = await userService.authenticateUser(username, password);
    }

    // Fallback to config-based authentication
    if (!user) {
      const validUser = req.config.appLogin.find(configUser => 
        configUser.username === username && configUser.password === password
      );

      if (validUser) {
        user = {
          id: null, // Config users don't have IDs
          username: validUser.username,
          role: 'admin', // Config users are treated as admins for backward compatibility
          adminId: null
        };
      }
    }

    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Generate JWT token with role information
    const tokenPayload = {
      userId: user.id,
      username: user.username,
      role: user.role,
      adminId: user.adminId
    };

    const token = jwt.sign(
      tokenPayload,
      req.config.jwt.secret,
      { expiresIn: req.config.jwt.expiresIn }
    );

    res.json({
      success: true,
      token,
      user: {
        id: user.id,
        username: user.username,
        role: user.role,
        requiresYouTubeAuth: user.role === 'admin'
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

    // Only admins can perform YouTube OAuth
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'YouTube authentication only allowed for admins' });
    }

    // Exchange server auth code for tokens
    const tokens = await googleOAuth.exchangeCodeForTokens(
      serverAuthCode,
      req.config.oauth
    );

    if (!tokens) {
      return res.status(400).json({ error: 'Failed to exchange auth code' });
    }

    // Store tokens using enhanced token store
    await tokenStore.storeTokens(req.user.userId || req.user.username, tokens);

    res.json({
      success: true,
      message: 'YouTube authentication successful'
    });

  } catch (error) {
    console.error('Code exchange error:', error);
    res.status(500).json({ error: 'Failed to exchange auth code' });
  }
};

// User Management Endpoints (Admin only)

const createUser = async (req, res) => {
  try {
    const { username, password } = req.body;
    
    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password required' });
    }

    // Only admins can create users
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can create users' });
    }

    const newUser = await userService.createUser(
      username, 
      password, 
      'user', 
      req.user.userId
    );

    res.json({
      success: true,
      user: {
        id: newUser.id,
        username: newUser.username,
        role: newUser.role,
        createdAt: newUser.created_at
      }
    });

  } catch (error) {
    console.error('Create user error:', error);
    if (error.message === 'Username already exists') {
      return res.status(409).json({ error: error.message });
    }
    res.status(500).json({ error: 'Failed to create user' });
  }
};

const getUsers = async (req, res) => {
  try {
    // Only admins can view users
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can view users' });
    }

    const users = await userService.getUsersByAdmin(req.user.userId);

    res.json({
      success: true,
      users: users.map(user => ({
        id: user.id,
        username: user.username,
        role: user.role,
        createdAt: user.created_at,
        updatedAt: user.updated_at
      }))
    });

  } catch (error) {
    console.error('Get users error:', error);
    res.status(500).json({ error: 'Failed to get users' });
  }
};

const updateUser = async (req, res) => {
  try {
    const { userId } = req.params;
    const { password } = req.body;
    
    if (!password) {
      return res.status(400).json({ error: 'Password required' });
    }

    // Only admins can update users
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can update users' });
    }

    // Verify the user belongs to this admin
    const targetUser = await userService.getUserById(parseInt(userId));
    if (!targetUser || targetUser.admin_id !== req.user.userId) {
      return res.status(404).json({ error: 'User not found or access denied' });
    }

    const updatedUser = await userService.updateUserPassword(parseInt(userId), password);

    if (!updatedUser) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({
      success: true,
      message: 'User password updated successfully'
    });

  } catch (error) {
    console.error('Update user error:', error);
    res.status(500).json({ error: 'Failed to update user' });
  }
};

const deleteUser = async (req, res) => {
  try {
    const { userId } = req.params;

    // Only admins can delete users
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can delete users' });
    }

    // Verify the user belongs to this admin
    const targetUser = await userService.getUserById(parseInt(userId));
    if (!targetUser || targetUser.admin_id !== req.user.userId) {
      return res.status(404).json({ error: 'User not found or access denied' });
    }

    const deletedUser = await userService.deleteUser(parseInt(userId));

    if (!deletedUser) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({
      success: true,
      message: 'User deleted successfully'
    });

  } catch (error) {
    console.error('Delete user error:', error);
    res.status(500).json({ error: 'Failed to delete user' });
  }
};

module.exports = {
  appLogin,
  exchangeCode,
  createUser,
  getUsers,
  updateUser,
  deleteUser
};