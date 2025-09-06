#!/usr/bin/env node

/**
 * Migration script to transition from file-based authentication to role-based system
 * This script helps existing installations upgrade to the new authentication system
 */

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

class Migration {
  constructor() {
    this.configPath = path.join(__dirname, 'local.config.json');
    this.tokensPath = path.join(__dirname, 'tokens.json');
  }

  async run() {
    console.log('🚀 Starting Press Connect Role-Based Authentication Migration');
    console.log('='.repeat(60));

    try {
      // Step 1: Check existing configuration
      await this.checkExistingConfig();

      // Step 2: Set up database if available
      const dbAvailable = await this.setupDatabase();

      // Step 3: Migrate existing tokens if any
      if (dbAvailable) {
        await this.migrateExistingTokens();
      }

      // Step 4: Create default admin user
      if (dbAvailable) {
        await this.createDefaultAdmin();
      }

      console.log('\n✅ Migration completed successfully!');
      console.log('\n📋 Next Steps:');
      console.log('1. Update your mobile app configuration');
      console.log('2. Test admin login and user creation');
      console.log('3. Create users for your team through the admin interface');
      console.log('4. Remove old authentication methods if desired');

    } catch (error) {
      console.error('\n❌ Migration failed:', error.message);
      console.log('\n🔧 The system will continue to work with file-based storage');
      console.log('   Database features will be available once database connection is established');
    }
  }

  async checkExistingConfig() {
    console.log('\n📋 Checking existing configuration...');

    // Check if config file exists
    if (fs.existsSync(this.configPath)) {
      const config = JSON.parse(fs.readFileSync(this.configPath, 'utf8'));
      console.log('✅ Configuration file found');
      
      // Validate required fields
      if (!config.appLogin || !config.oauth || !config.jwt) {
        throw new Error('Invalid configuration file structure');
      }
      
      console.log(`   - Admin users: ${config.appLogin.length}`);
      console.log(`   - OAuth client ID: ${config.oauth.clientId ? '✅ Configured' : '❌ Missing'}`);
      console.log(`   - JWT secret: ${config.jwt.secret ? '✅ Configured' : '❌ Missing'}`);
    } else {
      console.log('⚠️  Configuration file not found, creating default...');
      await this.createDefaultConfig();
    }

    // Check tokens file
    if (fs.existsSync(this.tokensPath)) {
      const tokens = JSON.parse(fs.readFileSync(this.tokensPath, 'utf8'));
      const userCount = Object.keys(tokens).length;
      console.log(`✅ Found existing tokens for ${userCount} user(s)`);
    } else {
      console.log('📝 No existing tokens found');
    }
  }

  async createDefaultConfig() {
    const defaultConfig = {
      appLogin: [
        { 
          username: "admin", 
          password: "admin123" 
        }
      ],
      oauth: {
        clientId: "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com",
        redirectUri: "com.example.press_connect:/oauth2redirect"
      },
      jwt: {
        secret: this.generateSecretKey(),
        expiresIn: "24h"
      }
    };

    fs.writeFileSync(this.configPath, JSON.stringify(defaultConfig, null, 2));
    console.log('✅ Default configuration created');
    console.log('⚠️  Please update the OAuth client ID in local.config.json');
  }

  generateSecretKey() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    for (let i = 0; i < 64; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }

  async setupDatabase() {
    console.log('\n🗃️  Setting up database...');

    const dbConfig = {
      host: process.env.DB_HOST || 'localhost',
      port: process.env.DB_PORT || 5432,
      database: process.env.DB_NAME || 'press_connect',
      user: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || 'password',
    };

    try {
      this.pool = new Pool(dbConfig);
      await this.pool.query('SELECT NOW()');
      console.log('✅ Database connection established');

      // Create tables
      await this.createTables();
      return true;
    } catch (error) {
      console.log('⚠️  Database not available, using file-based storage');
      console.log(`   Error: ${error.message}`);
      return false;
    }
  }

  async createTables() {
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
        admin_id INTEGER UNIQUE NOT NULL REFERENCES users(id),
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

    await this.pool.query(createUsersTable);
    await this.pool.query(createOAuthTokensTable);
    await this.pool.query(createSessionsTable);
    await this.pool.query(createIndexes);
    
    console.log('✅ Database tables created/verified');
  }

  async migrateExistingTokens() {
    console.log('\n🔄 Migrating existing tokens...');

    if (!fs.existsSync(this.tokensPath)) {
      console.log('📝 No tokens to migrate');
      return;
    }

    const tokens = JSON.parse(fs.readFileSync(this.tokensPath, 'utf8'));
    const usernames = Object.keys(tokens);

    if (usernames.length === 0) {
      console.log('📝 No tokens to migrate');
      return;
    }

    // For migration, assume the first user with tokens is an admin
    const adminUsername = usernames[0];
    console.log(`🔄 Migrating tokens for admin user: ${adminUsername}`);

    // Check if admin user exists
    const checkAdmin = await this.pool.query(
      'SELECT id FROM users WHERE username = $1 AND role = $2',
      [adminUsername, 'admin']
    );

    if (checkAdmin.rows.length > 0) {
      const adminId = checkAdmin.rows[0].id;
      const userTokens = tokens[adminUsername];

      // Store tokens
      await this.pool.query(`
        INSERT INTO oauth_tokens (admin_id, access_token, refresh_token, expires_at, updated_at)
        VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
        ON CONFLICT (admin_id) 
        DO UPDATE SET 
          access_token = EXCLUDED.access_token,
          refresh_token = EXCLUDED.refresh_token,
          expires_at = EXCLUDED.expires_at,
          updated_at = CURRENT_TIMESTAMP;
      `, [
        adminId,
        userTokens.access_token,
        userTokens.refresh_token || null,
        userTokens.expires_in || null
      ]);

      console.log('✅ Tokens migrated successfully');
    } else {
      console.log('⚠️  Admin user not found in database, tokens will be available after admin creation');
    }
  }

  async createDefaultAdmin() {
    console.log('\n👤 Creating default admin user...');

    const config = JSON.parse(fs.readFileSync(this.configPath, 'utf8'));
    const adminConfig = config.appLogin[0];

    if (!adminConfig) {
      console.log('⚠️  No admin configuration found');
      return;
    }

    // Check if admin already exists
    const checkQuery = 'SELECT COUNT(*) as count FROM users WHERE username = $1';
    const checkResult = await this.pool.query(checkQuery, [adminConfig.username]);
    
    if (parseInt(checkResult.rows[0].count) > 0) {
      console.log(`✅ Admin user '${adminConfig.username}' already exists`);
      return;
    }

    // Hash password
    const bcrypt = require('bcryptjs');
    const saltRounds = 10;
    const passwordHash = await bcrypt.hash(adminConfig.password, saltRounds);

    // Create admin user
    const insertQuery = `
      INSERT INTO users (username, password_hash, role, admin_id)
      VALUES ($1, $2, $3, $4)
      RETURNING id, username, role;
    `;

    const result = await this.pool.query(insertQuery, [
      adminConfig.username,
      passwordHash,
      'admin',
      null
    ]);

    console.log(`✅ Admin user '${result.rows[0].username}' created successfully`);
  }
}

// Run migration if called directly
if (require.main === module) {
  const migration = new Migration();
  migration.run().catch(console.error);
}

module.exports = Migration;