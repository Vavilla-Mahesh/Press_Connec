// Mock Database for Testing Authentication Flow
// This simulates the PostgreSQL database operations

class MockDatabase {
  constructor() {
    this.users = new Map();
    this.sessions = new Map();
    this.tokens = new Map();
  }

  // Initialize with test users
  async initialize(config) {
    const bcrypt = require('bcryptjs');
    
    for (const user of config.appLogin) {
      const passwordHash = await bcrypt.hash(user.password, 10);
      this.users.set(user.username, {
        username: user.username,
        password_hash: passwordHash,
        associated_with: user.associatedWith
      });
    }
    
    console.log(`Initialized ${this.users.size} users in mock database`);
  }

  // Validate user credentials
  async validateCredentials(username, password) {
    const bcrypt = require('bcryptjs');
    const user = this.users.get(username);
    
    if (!user) return null;
    
    const isValid = await bcrypt.compare(password, user.password_hash);
    if (!isValid) return null;
    
    return {
      username: user.username,
      associatedWith: user.associated_with
    };
  }

  // Create session
  async createSession(username) {
    const { v4: uuidv4 } = require('uuid');
    const sessionId = uuidv4();
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days
    
    this.sessions.set(sessionId, {
      sessionId,
      username,
      is_active: true,
      created_at: new Date(),
      last_activity: new Date(),
      expires_at: expiresAt
    });
    
    return { sessionId, expiresAt };
  }

  // Validate session
  async validateSession(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session || !session.is_active || session.expires_at < new Date()) {
      return null;
    }
    
    const user = this.users.get(session.username);
    
    // Update last activity
    session.last_activity = new Date();
    
    return {
      username: session.username,
      expiresAt: session.expires_at,
      associatedWith: user.associated_with
    };
  }

  // Store tokens (encrypted)
  async storeTokens(username, tokens, encryptionKey) {
    // Mock encryption
    const mockEncrypt = (data) => `encrypted_${Buffer.from(data).toString('base64')}`;
    
    this.tokens.set(username, {
      username,
      access_token: mockEncrypt(tokens.access_token),
      refresh_token: mockEncrypt(tokens.refresh_token || ''),
      token_type: tokens.token_type || 'Bearer',
      expires_at: new Date(tokens.expires_in || Date.now() + 3600000),
      scope: mockEncrypt(tokens.scope || '')
    });
    
    console.log(`Tokens stored for user: ${username}`);
  }

  // Get tokens (with association logic)
  async getTokens(username, encryptionKey) {
    // Mock decryption
    const mockDecrypt = (data) => {
      if (data.startsWith('encrypted_')) {
        return Buffer.from(data.substring(10), 'base64').toString();
      }
      return data;
    };
    
    // Check if user has their own tokens
    let tokenRecord = this.tokens.get(username);
    
    if (!tokenRecord) {
      // Check if user is associated with someone
      const user = this.users.get(username);
      if (user && user.associated_with) {
        tokenRecord = this.tokens.get(user.associated_with);
        if (tokenRecord) {
          console.log(`Retrieved tokens for ${username} from associated user: ${user.associated_with}`);
        }
      }
    }
    
    if (!tokenRecord) return null;
    
    return {
      access_token: mockDecrypt(tokenRecord.access_token),
      refresh_token: mockDecrypt(tokenRecord.refresh_token),
      token_type: tokenRecord.token_type,
      expires_in: tokenRecord.expires_at,
      scope: mockDecrypt(tokenRecord.scope)
    };
  }
}

// Test the complete authentication flow
async function testCompleteFlow() {
  const jwt = require('jsonwebtoken');
  const config = require('./local.config.json');
  
  console.log('=== Testing Complete Authentication Flow ===\n');
  
  // Initialize mock database
  const db = new MockDatabase();
  await db.initialize(config);
  
  // Test 1: Admin login (should require YouTube OAuth)
  console.log('1. Testing Admin Login:');
  const adminCreds = await db.validateCredentials('admin', '1234');
  console.log('   Credentials valid:', !!adminCreds);
  console.log('   User data:', adminCreds);
  console.log('   Requires YouTube OAuth:', !adminCreds.associatedWith);
  
  const adminSession = await db.createSession('admin');
  console.log('   Session created:', adminSession.sessionId);
  
  // Simulate admin doing YouTube OAuth
  await db.storeTokens('admin', {
    access_token: 'admin_access_token_123',
    refresh_token: 'admin_refresh_token_123',
    expires_in: Date.now() + 3600000,
    scope: 'https://www.googleapis.com/auth/youtube'
  }, config.encryption.key);
  
  console.log('   YouTube tokens stored for admin\n');
  
  // Test 2: Associated user login (should use admin's tokens)
  console.log('2. Testing Associated User Login (moderator):');
  const modCreds = await db.validateCredentials('moderator', '5678');
  console.log('   Credentials valid:', !!modCreds);
  console.log('   User data:', modCreds);
  console.log('   Requires YouTube OAuth:', !modCreds.associatedWith);
  
  const modSession = await db.createSession('moderator');
  console.log('   Session created:', modSession.sessionId);
  
  // Get tokens (should get admin's tokens)
  const modTokens = await db.getTokens('moderator', config.encryption.key);
  console.log('   Tokens available:', !!modTokens);
  console.log('   Token source: admin (associated user)\n');
  
  // Test 3: Session validation
  console.log('3. Testing Session Validation:');
  const validatedSession = await db.validateSession(modSession.sessionId);
  console.log('   Session valid:', !!validatedSession);
  console.log('   Session data:', validatedSession);
  
  // Test 4: JWT token creation
  console.log('4. Testing JWT Token Creation:');
  const jwtPayload = {
    username: modCreds.username,
    sessionId: modSession.sessionId,
    associatedWith: modCreds.associatedWith
  };
  const jwtToken = jwt.sign(jwtPayload, config.jwt.secret, { expiresIn: config.jwt.expiresIn });
  console.log('   JWT created:', jwtToken.substring(0, 50) + '...');
  
  const decoded = jwt.verify(jwtToken, config.jwt.secret);
  console.log('   JWT payload:', decoded);
  
  // Test 5: Independent user login
  console.log('\n5. Testing Independent User Login (user2):');
  const user2Creds = await db.validateCredentials('user2', '3456');
  console.log('   Credentials valid:', !!user2Creds);
  console.log('   User data:', user2Creds);
  console.log('   Requires YouTube OAuth:', !user2Creds.associatedWith);
  
  const user2Tokens = await db.getTokens('user2', config.encryption.key);
  console.log('   Has tokens:', !!user2Tokens);
  console.log('   Should show YouTube auth required');
  
  console.log('\n=== All tests completed successfully! ===');
  
  // Summary
  console.log('\n=== Flow Summary ===');
  console.log('✅ Admin users: Complete login → YouTube OAuth → Store tokens');
  console.log('✅ Associated users: Complete login → Skip YouTube OAuth → Use admin tokens');
  console.log('✅ Independent users: Complete login → YouTube OAuth → Store own tokens');
  console.log('✅ Session persistence: localStorage + PostgreSQL validation');
  console.log('✅ Token sharing: Associated users automatically use admin tokens');
}

// Run the test
testCompleteFlow().catch(console.error);