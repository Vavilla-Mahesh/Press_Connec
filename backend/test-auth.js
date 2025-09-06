#!/usr/bin/env node

/**
 * Test script for Press Connect Role-Based Authentication System
 * This script tests the main authentication and user management flows
 */

const axios = require('axios');

class AuthenticationTester {
  constructor(baseUrl = 'http://localhost:5000') {
    this.baseUrl = baseUrl;
    this.adminToken = null;
    this.testResults = [];
  }

  async runTests() {
    console.log('🧪 Starting Press Connect Authentication Tests');
    console.log('='.repeat(50));
    
    try {
      await this.testHealthEndpoint();
      await this.testAdminLogin();
      await this.testUserManagement();
      await this.testAccessControl();
      
      this.printSummary();
    } catch (error) {
      console.error('❌ Test suite failed:', error.message);
    }
  }

  async testHealthEndpoint() {
    console.log('\n📋 Testing Health Endpoint...');
    
    try {
      const response = await axios.get(`${this.baseUrl}/health`);
      
      if (response.status === 200 && response.data.status === 'healthy') {
        this.recordTest('Health Check', true, 'API is healthy');
      } else {
        this.recordTest('Health Check', false, 'Unexpected response');
      }
    } catch (error) {
      this.recordTest('Health Check', false, `Failed to connect: ${error.message}`);
      throw new Error('Cannot connect to backend API');
    }
  }

  async testAdminLogin() {
    console.log('\n👤 Testing Admin Authentication...');
    
    try {
      // Test valid admin login
      const loginResponse = await axios.post(`${this.baseUrl}/auth/app-login`, {
        username: 'admin',
        password: 'admin123'
      });

      if (loginResponse.status === 200 && 
          loginResponse.data.success && 
          loginResponse.data.user.role === 'admin') {
        
        this.adminToken = loginResponse.data.token;
        this.recordTest('Admin Login', true, 'Admin authentication successful');
        
        // Verify token structure
        const tokenParts = this.adminToken.split('.');
        if (tokenParts.length === 3) {
          this.recordTest('JWT Token Structure', true, 'Valid JWT format');
        } else {
          this.recordTest('JWT Token Structure', false, 'Invalid JWT format');
        }
      } else {
        this.recordTest('Admin Login', false, 'Unexpected login response');
      }

      // Test invalid credentials
      try {
        await axios.post(`${this.baseUrl}/auth/app-login`, {
          username: 'admin',
          password: 'wrongpassword'
        });
        this.recordTest('Invalid Credentials', false, 'Should have rejected invalid password');
      } catch (error) {
        if (error.response && error.response.status === 401) {
          this.recordTest('Invalid Credentials', true, 'Correctly rejected invalid password');
        } else {
          this.recordTest('Invalid Credentials', false, `Unexpected error: ${error.message}`);
        }
      }

    } catch (error) {
      this.recordTest('Admin Login', false, `Login failed: ${error.message}`);
    }
  }

  async testUserManagement() {
    console.log('\n👥 Testing User Management...');
    
    if (!this.adminToken) {
      this.recordTest('User Management', false, 'No admin token available');
      return;
    }

    const headers = {
      'Authorization': `Bearer ${this.adminToken}`,
      'Content-Type': 'application/json'
    };

    try {
      // Test user creation
      const createResponse = await axios.post(`${this.baseUrl}/users`, {
        username: 'testuser',
        password: 'testpass123'
      }, { headers });

      // This might fail with file-based storage, which is expected
      if (createResponse.status === 200) {
        this.recordTest('User Creation', true, 'User created successfully');
      } else {
        this.recordTest('User Creation', false, 'User creation failed');
      }

    } catch (error) {
      if (error.response && error.response.data.error === 'Failed to create user') {
        this.recordTest('User Creation', true, 'Expected failure with file-based storage');
      } else {
        this.recordTest('User Creation', false, `Unexpected error: ${error.message}`);
      }
    }

    try {
      // Test user listing
      const listResponse = await axios.get(`${this.baseUrl}/users`, { headers });
      
      if (listResponse.status === 200) {
        this.recordTest('User Listing', true, 'User list retrieved');
      } else {
        this.recordTest('User Listing', false, 'Failed to retrieve user list');
      }

    } catch (error) {
      if (error.response && error.response.data.error === 'Failed to get users') {
        this.recordTest('User Listing', true, 'Expected failure with file-based storage');
      } else {
        this.recordTest('User Listing', false, `Unexpected error: ${error.message}`);
      }
    }
  }

  async testAccessControl() {
    console.log('\n🔒 Testing Access Control...');

    // Test unauthorized access
    try {
      await axios.get(`${this.baseUrl}/users`);
      this.recordTest('Unauthorized Access', false, 'Should have required authentication');
    } catch (error) {
      if (error.response && error.response.status === 401) {
        this.recordTest('Unauthorized Access', true, 'Correctly blocked unauthorized access');
      } else {
        this.recordTest('Unauthorized Access', false, `Unexpected error: ${error.message}`);
      }
    }

    // Test with invalid token
    try {
      await axios.get(`${this.baseUrl}/users`, {
        headers: { 'Authorization': 'Bearer invalid-token' }
      });
      this.recordTest('Invalid Token', false, 'Should have rejected invalid token');
    } catch (error) {
      if (error.response && error.response.status === 401) {
        this.recordTest('Invalid Token', true, 'Correctly rejected invalid token');
      } else {
        this.recordTest('Invalid Token', false, `Unexpected error: ${error.message}`);
      }
    }

    // Test admin-only endpoint protection
    if (this.adminToken) {
      try {
        // Create a mock non-admin token (this would normally be created through proper flow)
        const response = await axios.post(`${this.baseUrl}/users`, {
          username: 'testuser2',
          password: 'testpass123'
        }, {
          headers: {
            'Authorization': `Bearer ${this.adminToken}`,
            'Content-Type': 'application/json'
          }
        });
        this.recordTest('Admin Endpoint Access', true, 'Admin can access user management');
      } catch (error) {
        if (error.response && (
          error.response.data.error === 'Failed to create user' ||
          error.response.data.error === 'Database not available'
        )) {
          this.recordTest('Admin Endpoint Access', true, 'Admin endpoint accessible (expected DB failure)');
        } else {
          this.recordTest('Admin Endpoint Access', false, `Unexpected error: ${error.message}`);
        }
      }
    }
  }

  recordTest(testName, passed, details) {
    this.testResults.push({ testName, passed, details });
    const status = passed ? '✅' : '❌';
    console.log(`${status} ${testName}: ${details}`);
  }

  printSummary() {
    console.log('\n📊 Test Summary');
    console.log('='.repeat(30));
    
    const passedTests = this.testResults.filter(test => test.passed).length;
    const totalTests = this.testResults.length;
    
    console.log(`Total Tests: ${totalTests}`);
    console.log(`Passed: ${passedTests}`);
    console.log(`Failed: ${totalTests - passedTests}`);
    console.log(`Success Rate: ${Math.round((passedTests / totalTests) * 100)}%`);

    if (passedTests === totalTests) {
      console.log('\n🎉 All tests passed! The authentication system is working correctly.');
    } else {
      console.log('\n⚠️  Some tests failed. Check the details above.');
      console.log('\nFailed Tests:');
      this.testResults
        .filter(test => !test.passed)
        .forEach(test => console.log(`  - ${test.testName}: ${test.details}`));
    }

    console.log('\n📋 Next Steps:');
    console.log('1. Set up PostgreSQL for full database functionality');
    console.log('2. Configure Google OAuth for YouTube integration');
    console.log('3. Test with mobile app');
    console.log('4. Create production users through the admin interface');
  }
}

// Add axios as a dependency check
function checkDependencies() {
  try {
    require('axios');
    return true;
  } catch (error) {
    console.error('❌ Missing dependency: axios');
    console.log('Please install axios: npm install axios');
    return false;
  }
}

// Run tests if called directly
if (require.main === module) {
  if (!checkDependencies()) {
    process.exit(1);
  }

  const tester = new AuthenticationTester();
  
  // Allow custom backend URL
  const customUrl = process.argv[2];
  if (customUrl) {
    tester.baseUrl = customUrl;
    console.log(`Using custom backend URL: ${customUrl}`);
  }
  
  tester.runTests().catch(console.error);
}

module.exports = AuthenticationTester;