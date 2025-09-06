const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

let pool = null;

const initializeDatabase = async (config) => {
  try {
    // Create connection pool
    pool = new Pool({
      host: config.database.host,
      port: config.database.port,
      database: config.database.database,
      user: config.database.user,
      password: config.database.password,
      ssl: config.database.ssl,
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    });

    // Test connection
    const client = await pool.connect();
    console.log('PostgreSQL connected successfully');
    
    // Create database schema
    await createDatabaseSchema(client, config);
    
    client.release();
    return pool;
  } catch (error) {
    console.error('Database initialization failed:', error);
    throw error;
  }
};

const createDatabaseSchema = async (client, config) => {
  try {
    // Enable pgcrypto extension for encryption
    await client.query('CREATE EXTENSION IF NOT EXISTS pgcrypto');

    // Create users table
    await client.query(`
      CREATE TABLE IF NOT EXISTS users (
        username VARCHAR(50) PRIMARY KEY,
        password_hash VARCHAR(255) NOT NULL,
        associated_with VARCHAR(50),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (associated_with) REFERENCES users(username)
      )
    `);

    // Create user sessions table
    await client.query(`
      CREATE TABLE IF NOT EXISTS user_sessions (
        session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        username VARCHAR(50) NOT NULL,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        expires_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP + INTERVAL '30 days'),
        FOREIGN KEY (username) REFERENCES users(username) ON DELETE CASCADE
      )
    `);

    // Create YouTube OAuth tokens table (encrypted storage)
    await client.query(`
      CREATE TABLE IF NOT EXISTS youtube_tokens (
        username VARCHAR(50) PRIMARY KEY,
        access_token TEXT NOT NULL,
        refresh_token TEXT NOT NULL,
        token_type VARCHAR(20) DEFAULT 'Bearer',
        expires_at TIMESTAMP NOT NULL,
        scope TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (username) REFERENCES users(username) ON DELETE CASCADE
      )
    `);

    // Create indexes for performance
    await client.query('CREATE INDEX IF NOT EXISTS idx_user_sessions_username ON user_sessions(username)');
    await client.query('CREATE INDEX IF NOT EXISTS idx_user_sessions_active ON user_sessions(is_active, expires_at)');
    await client.query('CREATE INDEX IF NOT EXISTS idx_youtube_tokens_expires ON youtube_tokens(expires_at)');

    console.log('Database schema created successfully');
  } catch (error) {
    console.error('Error creating database schema:', error);
    throw error;
  }
};

const getPool = () => {
  if (!pool) {
    throw new Error('Database not initialized');
  }
  return pool;
};

const closeDatabase = async () => {
  if (pool) {
    await pool.end();
    pool = null;
  }
};

module.exports = {
  initializeDatabase,
  getPool,
  closeDatabase
};