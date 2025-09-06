const bcrypt = require('bcryptjs');

// Test password hashing and validation
async function testPasswordHashing() {
  console.log('Testing password hashing...');
  
  const password = '1234';
  const hash = await bcrypt.hash(password, 10);
  console.log('Generated hash:', hash);
  
  const isValid = await bcrypt.compare(password, hash);
  console.log('Password validation:', isValid);
  
  const isInvalid = await bcrypt.compare('wrong', hash);
  console.log('Wrong password validation:', isInvalid);
}

// Test user association logic
function testUserAssociations() {
  console.log('\nTesting user association logic...');
  
  const users = [
    { username: "admin", password: "1234", associatedWith: null },
    { username: "moderator", password: "5678", associatedWith: "admin" },
    { username: "user1", password: "9012", associatedWith: "admin" },
    { username: "user2", password: "3456", associatedWith: null }
  ];
  
  for (const user of users) {
    console.log(`User: ${user.username}`);
    console.log(`  - Associated with: ${user.associatedWith || 'None (independent)'}`);
    console.log(`  - Token source: ${user.associatedWith ? user.associatedWith : user.username}`);
    console.log(`  - Requires YouTube OAuth: ${!user.associatedWith}`);
  }
}

// Test JWT token structure
function testJWTStructure() {
  console.log('\nTesting JWT token structure...');
  
  const jwt = require('jsonwebtoken');
  const secret = 'test_secret';
  
  const payload = {
    username: 'moderator',
    sessionId: 'sess_abc123',
    associatedWith: 'admin'
  };
  
  const token = jwt.sign(payload, secret, { expiresIn: '30d' });
  console.log('Generated token:', token);
  
  const decoded = jwt.verify(token, secret);
  console.log('Decoded token:', decoded);
}

// Run tests
async function runTests() {
  await testPasswordHashing();
  testUserAssociations();
  testJWTStructure();
  console.log('\nAll tests completed successfully!');
}

runTests().catch(console.error);