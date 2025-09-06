const bcrypt = require('bcryptjs');
const { getPool } = require('./database');

// Create a new user (admin only)
const createUser = async (req, res) => {
  try {
    const { username, password, associatedWith } = req.body;
    
    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password required' });
    }

    // Check if user already exists
    const pool = getPool();
    const client = await pool.connect();
    
    try {
      const existingUser = await client.query(
        'SELECT username FROM users WHERE username = $1',
        [username]
      );
      
      if (existingUser.rows.length > 0) {
        return res.status(409).json({ error: 'User already exists' });
      }

      // Validate associatedWith user exists if provided
      if (associatedWith) {
        const associatedUser = await client.query(
          'SELECT username FROM users WHERE username = $1',
          [associatedWith]
        );
        
        if (associatedUser.rows.length === 0) {
          return res.status(400).json({ error: 'Associated user does not exist' });
        }
      }

      // Hash password
      const passwordHash = await bcrypt.hash(password, 10);
      
      // Insert user
      await client.query(
        'INSERT INTO users (username, password_hash, associated_with) VALUES ($1, $2, $3)',
        [username, passwordHash, associatedWith || null]
      );
      
      res.status(201).json({
        success: true,
        message: 'User created successfully',
        user: {
          username,
          associatedWith: associatedWith || null
        }
      });

    } finally {
      client.release();
    }

  } catch (error) {
    console.error('Create user error:', error);
    res.status(500).json({ error: 'Failed to create user' });
  }
};

// Get all users (admin only)
const getUsers = async (req, res) => {
  try {
    const pool = getPool();
    const client = await pool.connect();
    
    try {
      const result = await client.query(`
        SELECT 
          username, 
          associated_with, 
          created_at,
          (SELECT COUNT(*) FROM user_sessions WHERE username = users.username AND is_active = true) as active_sessions
        FROM users 
        ORDER BY created_at DESC
      `);
      
      res.json({
        success: true,
        users: result.rows
      });

    } finally {
      client.release();
    }

  } catch (error) {
    console.error('Get users error:', error);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
};

// Update user (admin only)
const updateUser = async (req, res) => {
  try {
    const { username } = req.params;
    const { password, associatedWith } = req.body;
    
    const pool = getPool();
    const client = await pool.connect();
    
    try {
      // Check if user exists
      const existingUser = await client.query(
        'SELECT username FROM users WHERE username = $1',
        [username]
      );
      
      if (existingUser.rows.length === 0) {
        return res.status(404).json({ error: 'User not found' });
      }

      // Validate associatedWith user exists if provided
      if (associatedWith) {
        const associatedUser = await client.query(
          'SELECT username FROM users WHERE username = $1',
          [associatedWith]
        );
        
        if (associatedUser.rows.length === 0) {
          return res.status(400).json({ error: 'Associated user does not exist' });
        }
      }

      let updateQuery = 'UPDATE users SET ';
      let updateParams = [];
      let paramCount = 0;

      if (password) {
        paramCount++;
        const passwordHash = await bcrypt.hash(password, 10);
        updateQuery += `password_hash = $${paramCount}`;
        updateParams.push(passwordHash);
      }

      if (associatedWith !== undefined) {
        if (paramCount > 0) updateQuery += ', ';
        paramCount++;
        updateQuery += `associated_with = $${paramCount}`;
        updateParams.push(associatedWith || null);
      }

      if (paramCount === 0) {
        return res.status(400).json({ error: 'No fields to update' });
      }

      paramCount++;
      updateQuery += ` WHERE username = $${paramCount}`;
      updateParams.push(username);

      await client.query(updateQuery, updateParams);
      
      res.json({
        success: true,
        message: 'User updated successfully'
      });

    } finally {
      client.release();
    }

  } catch (error) {
    console.error('Update user error:', error);
    res.status(500).json({ error: 'Failed to update user' });
  }
};

// Delete user (admin only)
const deleteUser = async (req, res) => {
  try {
    const { username } = req.params;
    
    // Prevent deletion of the requesting admin user
    if (username === req.user.username) {
      return res.status(400).json({ error: 'Cannot delete your own account' });
    }

    const pool = getPool();
    const client = await pool.connect();
    
    try {
      const result = await client.query(
        'DELETE FROM users WHERE username = $1',
        [username]
      );
      
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'User not found' });
      }

      res.json({
        success: true,
        message: 'User deleted successfully'
      });

    } finally {
      client.release();
    }

  } catch (error) {
    console.error('Delete user error:', error);
    res.status(500).json({ error: 'Failed to delete user' });
  }
};

// Get user statistics (admin only)
const getUserStats = async (req, res) => {
  try {
    const pool = getPool();
    const client = await pool.connect();
    
    try {
      const stats = await client.query(`
        SELECT 
          (SELECT COUNT(*) FROM users) as total_users,
          (SELECT COUNT(*) FROM users WHERE associated_with IS NULL) as admin_users,
          (SELECT COUNT(*) FROM users WHERE associated_with IS NOT NULL) as regular_users,
          (SELECT COUNT(*) FROM user_sessions WHERE is_active = true) as active_sessions,
          (SELECT COUNT(*) FROM youtube_tokens) as users_with_youtube_auth
      `);
      
      res.json({
        success: true,
        stats: stats.rows[0]
      });

    } finally {
      client.release();
    }

  } catch (error) {
    console.error('Get user stats error:', error);
    res.status(500).json({ error: 'Failed to fetch user statistics' });
  }
};

module.exports = {
  createUser,
  getUsers,
  updateUser,
  deleteUser,
  getUserStats
};