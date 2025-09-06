const { Pool } = require('pg');

class Database {
  constructor() {
    this.pool = null;
  }

  async init() {
    this.pool = new Pool({
      host: process.env.DB_HOST || 'localhost',
      port: process.env.DB_PORT || 5432,
      database: process.env.DB_NAME || 'press_connect',
      user: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || 'password',
      ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false
    });

    try {
      await this.pool.query('SELECT NOW()');
      console.log('✅ Database connection established');
      await this.createTables();
    } catch (error) {
      console.error('❌ Database connection failed:', error.message);
      console.log('📝 Using fallback file-based storage for development');
      this.pool = null; // Fallback to file-based storage
    }
  }

  async createTables() {
    if (!this.pool) return;

    const createUsersTable = `
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(255) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        role VARCHAR(50) NOT NULL DEFAULT 'user',
        admin_id INTEGER REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `;

    const createOAuthTokensTable = `
      CREATE TABLE IF NOT EXISTS oauth_tokens (
        id SERIAL PRIMARY KEY,
        admin_id INTEGER NOT NULL REFERENCES users(id),
        access_token TEXT NOT NULL,
        refresh_token TEXT,
        expires_at BIGINT,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `;

    const createSessionsTable = `
      CREATE TABLE IF NOT EXISTS sessions (
        id SERIAL PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id),
        token TEXT NOT NULL,
        expires_at TIMESTAMP NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `;

    const createIndexes = `
      CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
      CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
      CREATE INDEX IF NOT EXISTS idx_oauth_tokens_admin_id ON oauth_tokens(admin_id);
      CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
      CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token);
    `;

    try {
      await this.pool.query(createUsersTable);
      await this.pool.query(createOAuthTokensTable);
      await this.pool.query(createSessionsTable);
      await this.pool.query(createIndexes);
      console.log('✅ Database tables created/verified');
    } catch (error) {
      console.error('❌ Failed to create database tables:', error.message);
      throw error;
    }
  }

  async query(text, params) {
    if (!this.pool) {
      throw new Error('Database not available');
    }
    return this.pool.query(text, params);
  }

  async getClient() {
    if (!this.pool) {
      throw new Error('Database not available');
    }
    return this.pool.connect();
  }

  isAvailable() {
    return this.pool !== null;
  }

  async close() {
    if (this.pool) {
      await this.pool.end();
    }
  }
}

module.exports = new Database();