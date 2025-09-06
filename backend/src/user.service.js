const database = require('./database');
const bcrypt = require('bcryptjs');

class UserService {
  // Create a new user (admin can create regular users)
  async createUser(username, password, role = 'user', adminId = null) {
    if (!database.isAvailable()) {
      throw new Error('Database not available');
    }

    // Hash password
    const saltRounds = 10;
    const passwordHash = await bcrypt.hash(password, saltRounds);

    const query = `
      INSERT INTO users (username, password_hash, role, admin_id)
      VALUES ($1, $2, $3, $4)
      RETURNING id, username, role, admin_id, created_at;
    `;

    try {
      const result = await database.query(query, [username, passwordHash, role, adminId]);
      return result.rows[0];
    } catch (error) {
      if (error.code === '23505') { // Unique constraint violation
        throw new Error('Username already exists');
      }
      throw error;
    }
  }

  // Authenticate user with username and password
  async authenticateUser(username, password) {
    // Try database first
    if (database.isAvailable()) {
      const query = `
        SELECT id, username, password_hash, role, admin_id
        FROM users 
        WHERE username = $1;
      `;

      const result = await database.query(query, [username]);
      
      if (result.rows.length === 0) {
        return null;
      }

      const user = result.rows[0];
      const isValidPassword = await bcrypt.compare(password, user.password_hash);
      
      if (!isValidPassword) {
        return null;
      }

      return {
        id: user.id,
        username: user.username,
        role: user.role,
        adminId: user.admin_id
      };
    } else {
      // Fallback to config-based authentication (existing behavior)
      return null; // Will be handled by existing auth controller
    }
  }

  // Get user by ID
  async getUserById(userId) {
    if (!database.isAvailable()) {
      throw new Error('Database not available');
    }

    const query = `
      SELECT id, username, role, admin_id, created_at, updated_at
      FROM users 
      WHERE id = $1;
    `;

    const result = await database.query(query, [userId]);
    return result.rows.length > 0 ? result.rows[0] : null;
  }

  // Get user by username
  async getUserByUsername(username) {
    if (!database.isAvailable()) {
      throw new Error('Database not available');
    }

    const query = `
      SELECT id, username, role, admin_id, created_at, updated_at
      FROM users 
      WHERE username = $1;
    `;

    const result = await database.query(query, [username]);
    return result.rows.length > 0 ? result.rows[0] : null;
  }

  // Get all users created by an admin
  async getUsersByAdmin(adminId) {
    if (!database.isAvailable()) {
      throw new Error('Database not available');
    }

    const query = `
      SELECT id, username, role, created_at, updated_at
      FROM users 
      WHERE admin_id = $1
      ORDER BY created_at DESC;
    `;

    const result = await database.query(query, [adminId]);
    return result.rows;
  }

  // Update user password
  async updateUserPassword(userId, newPassword) {
    if (!database.isAvailable()) {
      throw new Error('Database not available');
    }

    const saltRounds = 10;
    const passwordHash = await bcrypt.hash(newPassword, saltRounds);

    const query = `
      UPDATE users 
      SET password_hash = $1, updated_at = CURRENT_TIMESTAMP
      WHERE id = $2
      RETURNING id, username, role;
    `;

    const result = await database.query(query, [passwordHash, userId]);
    return result.rows.length > 0 ? result.rows[0] : null;
  }

  // Delete user
  async deleteUser(userId) {
    if (!database.isAvailable()) {
      throw new Error('Database not available');
    }

    const query = `DELETE FROM users WHERE id = $1 RETURNING id, username;`;
    const result = await database.query(query, [userId]);
    return result.rows.length > 0 ? result.rows[0] : null;
  }

  // Create default admin user if none exists
  async createDefaultAdmin(username, password) {
    if (!database.isAvailable()) {
      return null;
    }

    try {
      // Check if any admin exists
      const checkQuery = `SELECT COUNT(*) as count FROM users WHERE role = 'admin';`;
      const checkResult = await database.query(checkQuery);
      
      if (parseInt(checkResult.rows[0].count) > 0) {
        console.log('Admin user already exists');
        return null;
      }

      // Create admin user
      const admin = await this.createUser(username, password, 'admin', null);
      console.log(`✅ Default admin user created: ${username}`);
      return admin;
    } catch (error) {
      console.error('Failed to create default admin:', error.message);
      return null;
    }
  }

  // Check if user has admin privileges
  async isAdmin(userId) {
    if (!database.isAvailable()) {
      return false;
    }

    const query = `SELECT role FROM users WHERE id = $1;`;
    const result = await database.query(query, [userId]);
    
    return result.rows.length > 0 && result.rows[0].role === 'admin';
  }

  // Get admin for a regular user
  async getAdminForUser(userId) {
    if (!database.isAvailable()) {
      return null;
    }

    const query = `
      SELECT u2.id, u2.username, u2.role
      FROM users u1
      JOIN users u2 ON u1.admin_id = u2.id
      WHERE u1.id = $1 AND u2.role = 'admin';
    `;

    const result = await database.query(query, [userId]);
    return result.rows.length > 0 ? result.rows[0] : null;
  }
}

module.exports = new UserService();