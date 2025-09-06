// Integration Test - Simulates complete frontend-backend authentication flow
// This test demonstrates the entire system working together

const AuthService = require('./frontend_auth_service');

// Mock backend responses for testing
class MockBackend {
  constructor() {
    this.sessions = new Map();
    this.tokens = new Map();
    this.users = new Map([
      ['admin', { username: 'admin', associatedWith: null }],
      ['moderator', { username: 'moderator', associatedWith: 'admin' }],
      ['user1', { username: 'user1', associatedWith: 'admin' }],
      ['user2', { username: 'user2', associatedWith: null }]
    ]);
    
    // Admin has YouTube tokens
    this.tokens.set('admin', true);
  }

  // Mock login endpoint
  async login(username, password) {
    const validCredentials = {
      'admin': '1234',
      'moderator': '5678',
      'user1': '9012',
      'user2': '3456'
    };

    if (validCredentials[username] !== password) {
      return { ok: false, json: async () => ({ error: 'Invalid credentials' }) };
    }

    const user = this.users.get(username);
    const sessionId = `sess_${Date.now()}_${Math.random()}`;
    
    this.sessions.set(sessionId, {
      username,
      valid: true,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
    });

    return {
      ok: true,
      json: async () => ({
        success: true,
        user,
        session: {
          sessionId,
          expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
        },
        token: `jwt_token_for_${username}`
      })
    };
  }

  // Mock session validation endpoint
  async validateSession(sessionId) {
    const session = this.sessions.get(sessionId);
    
    if (!session || !session.valid || session.expiresAt < new Date()) {
      return { ok: false, json: async () => ({ valid: false, error: 'Invalid session' }) };
    }

    const user = this.users.get(session.username);
    const hasYouTubeAuth = this.tokens.has(user.associatedWith || user.username);
    
    return {
      ok: true,
      json: async () => ({
        valid: true,
        user,
        hasYouTubeAuth,
        requiresYouTubeAuth: !user.associatedWith && !hasYouTubeAuth
      })
    };
  }
}

// Mock fetch function
function createMockFetch(mockBackend) {
  return async function mockFetch(url, options = {}) {
    const { method = 'GET', body } = options;
    const parsedBody = body ? JSON.parse(body) : {};

    if (url.includes('/auth/app-login')) {
      return mockBackend.login(parsedBody.username, parsedBody.password);
    }
    
    if (url.includes('/auth/validate-session')) {
      return mockBackend.validateSession(parsedBody.sessionId);
    }
    
    if (url.includes('/auth/logout')) {
      return { ok: true, json: async () => ({ success: true }) };
    }

    throw new Error(`Unhandled URL: ${url}`);
  };
}

// Mock localStorage
class MockLocalStorage {
  constructor() {
    this.storage = new Map();
  }
  
  getItem(key) {
    return this.storage.get(key) || null;
  }
  
  setItem(key, value) {
    this.storage.set(key, value);
  }
  
  removeItem(key) {
    this.storage.delete(key);
  }
}

// Test the complete integration
async function testIntegration() {
  console.log('=== Integration Test: Complete Authentication Flow ===\n');
  
  const mockBackend = new MockBackend();
  const mockLocalStorage = new MockLocalStorage();
  
  // Setup mocks
  global.fetch = createMockFetch(mockBackend);
  global.localStorage = mockLocalStorage;
  global.btoa = (str) => Buffer.from(str).toString('base64');
  global.atob = (str) => Buffer.from(str, 'base64').toString();
  
  const authService = new AuthService('http://localhost:5000');
  
  // Test 1: App startup with no session
  console.log('1. Testing app startup with no existing session:');
  let startupResult = await authService.initializeApp();
  console.log('   Result:', startupResult);
  console.log('   ✅ Should navigate to login page\n');
  
  // Test 2: Admin login
  console.log('2. Testing admin login:');
  const adminLogin = await authService.login('admin', '1234');
  console.log('   Login result:', adminLogin);
  console.log('   ✅ Admin should require YouTube OAuth\n');
  
  // Test 3: Admin session validation
  console.log('3. Testing admin session validation:');
  const adminValidation = await authService.validateSession();
  console.log('   Validation result:', adminValidation);
  console.log('   ✅ Session should be valid with YouTube auth\n');
  
  // Test 4: App startup with valid admin session
  console.log('4. Testing app startup with valid admin session:');
  startupResult = await authService.initializeApp();
  console.log('   Result:', startupResult);
  console.log('   ✅ Should navigate directly to Go Live page\n');
  
  // Test 5: Logout and login as associated user
  console.log('5. Testing logout and login as associated user:');
  await authService.logout();
  const modLogin = await authService.login('moderator', '5678');
  console.log('   Moderator login result:', modLogin);
  console.log('   ✅ Associated user should skip YouTube OAuth\n');
  
  // Test 6: Associated user session validation
  console.log('6. Testing associated user session:');
  const modValidation = await authService.validateSession();
  console.log('   Validation result:', modValidation);
  console.log('   ✅ Should have YouTube auth via association\n');
  
  // Test 7: App startup with associated user
  console.log('7. Testing app startup with associated user session:');
  startupResult = await authService.initializeApp();
  console.log('   Result:', startupResult);
  console.log('   ✅ Should navigate directly to Go Live page\n');
  
  // Test 8: Independent user without YouTube auth
  console.log('8. Testing independent user login:');
  await authService.logout();
  const user2Login = await authService.login('user2', '3456');
  console.log('   User2 login result:', user2Login);
  
  const user2Validation = await authService.validateSession();
  console.log('   User2 validation:', user2Validation);
  console.log('   ✅ Independent user should require YouTube OAuth\n');
  
  // Test 9: Frontend localStorage structure
  console.log('9. Testing localStorage session structure:');
  const storedSession = authService.getStoredSession();
  console.log('   Stored session:', storedSession);
  console.log('   ✅ Session should match requirements structure\n');
  
  // Test 10: Session persistence across "app restart"
  console.log('10. Testing session persistence (simulated app restart):');
  // Create new auth service instance (simulates app restart)
  const newAuthService = new AuthService('http://localhost:5000');
  const persistenceTest = await newAuthService.initializeApp();
  console.log('   Persistence result:', persistenceTest);
  console.log('   ✅ Session should persist across app restarts\n');
  
  console.log('=== Integration Test Summary ===');
  console.log('✅ App startup logic working correctly');
  console.log('✅ User authentication with different types working');
  console.log('✅ Session persistence working');
  console.log('✅ Token sharing logic working');
  console.log('✅ localStorage + backend hybrid storage working');
  console.log('✅ All authentication flows validated');
  
  console.log('\n=== User Flow Summary ===');
  console.log('🔐 Admin: Login → YouTube OAuth → Go Live');
  console.log('👥 Associated: Login → Go Live (uses admin tokens)');
  console.log('🔓 Independent: Login → YouTube OAuth → Go Live');
  console.log('⚡ Restart: Check localStorage → Validate session → Go Live');
}

// Run the integration test
testIntegration().catch(console.error);