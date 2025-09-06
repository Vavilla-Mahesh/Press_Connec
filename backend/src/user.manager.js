const bcrypt = require('bcryptjs');
const { getPool } = require('./database');

const initializeUsers = async (config) => {
  const pool = getPool();
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    for (const user of config.appLogin) {
      // Check if user already exists
      const existingUser = await client.query(
        'SELECT username FROM users WHERE username = $1',
        [user.username]
      );
      
      if (existingUser.rows.length === 0) {
        // Hash password
        const passwordHash = await bcrypt.hash(user.password, 10);
        
        // Insert user
        await client.query(
          'INSERT INTO users (username, password_hash, associated_with) VALUES ($1, $2, $3)',
          [user.username, passwordHash, user.associatedWith]
        );
        
        console.log(`User ${user.username} created successfully`);
      } else {
        console.log(`User ${user.username} already exists`);
      }
    }
    
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error initializing users:', error);
    throw error;
  } finally {
    client.release();
  }
};

const validateUserCredentials = async (username, password) => {
  const pool = getPool();
  const client = await pool.connect();
  
  try {
    const result = await client.query(
      'SELECT username, password_hash, associated_with FROM users WHERE username = $1',
      [username]
    );
    
    if (result.rows.length === 0) {
      return null;
    }
    
    const user = result.rows[0];
    const isValid = await bcrypt.compare(password, user.password_hash);
    
    if (!isValid) {
      return null;
    }
    
    return {
      username: user.username,
      associatedWith: user.associated_with
    };
  } catch (error) {
    console.error('Error validating user credentials:', error);
    throw error;
  } finally {
    client.release();
  }
};

const createUserSession = async (username) => {
  const pool = getPool();
  const client = await pool.connect();
  
  try {
    // Deactivate existing sessions for this user
    await client.query(
      'UPDATE user_sessions SET is_active = false WHERE username = $1 AND is_active = true',
      [username]
    );
    
    // Create new session
    const result = await client.query(
      'INSERT INTO user_sessions (username) VALUES ($1) RETURNING session_id, expires_at',
      [username]
    );
    
    return {
      sessionId: result.rows[0].session_id,
      expiresAt: result.rows[0].expires_at
    };
  } catch (error) {
    console.error('Error creating user session:', error);
    throw error;
  } finally {
    client.release();
  }
};

const validateSession = async (sessionId) => {
  const pool = getPool();
  const client = await pool.connect();
  
  try {
    const result = await client.query(`
      SELECT s.username, s.expires_at, u.associated_with 
      FROM user_sessions s 
      JOIN users u ON s.username = u.username 
      WHERE s.session_id = $1 AND s.is_active = true AND s.expires_at > CURRENT_TIMESTAMP
    `, [sessionId]);
    
    if (result.rows.length === 0) {
      return null;
    }
    
    // Update last activity
    await client.query(
      'UPDATE user_sessions SET last_activity = CURRENT_TIMESTAMP WHERE session_id = $1',
      [sessionId]
    );
    
    return {
      username: result.rows[0].username,
      expiresAt: result.rows[0].expires_at,
      associatedWith: result.rows[0].associated_with
    };
  } catch (error) {
    console.error('Error validating session:', error);
    throw error;
  } finally {
    client.release();
  }
};

const deactivateSession = async (sessionId) => {
  const pool = getPool();
  const client = await pool.connect();
  
  try {
    await client.query(
      'UPDATE user_sessions SET is_active = false WHERE session_id = $1',
      [sessionId]
    );
  } catch (error) {
    console.error('Error deactivating session:', error);
    throw error;
  } finally {
    client.release();
  }
};

module.exports = {
  initializeUsers,
  validateUserCredentials,
  createUserSession,
  validateSession,
  deactivateSession
};