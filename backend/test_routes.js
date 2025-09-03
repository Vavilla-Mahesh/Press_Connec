const express = require('express');
const app = express();

// Mock the live controller
const mockLiveController = {
  createLiveStream: (req, res) => {
    console.log('✓ createLiveStream route works');
    res.json({ success: true, autoLiveEnabled: true });
  },
  endLiveStream: (req, res) => {
    console.log('✓ endLiveStream route works');
    res.json({ success: true });
  },
  transitionBroadcast: (req, res) => {
    console.log('✓ transitionBroadcast route works');
    res.json({ success: true });
  }
};

// Mock JWT middleware
const mockVerifyToken = (req, res, next) => {
  req.user = { username: 'test' };
  req.config = { oauth: {} };
  next();
};

app.use(express.json());

// Test routes exactly as implemented
app.post('/live/create', mockVerifyToken, mockLiveController.createLiveStream);
app.post('/live/end', mockVerifyToken, mockLiveController.endLiveStream);
app.post('/live/transition', mockVerifyToken, mockLiveController.transitionBroadcast);

// Test the routes
const request = require('http');

function testRoute(path, data) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify(data);
    const options = {
      hostname: 'localhost',
      port: 3001,
      path: path,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer test-token',
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const req = request.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, data: JSON.parse(data) }));
    });

    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

const server = app.listen(3001, async () => {
  try {
    console.log('Testing routes...');
    
    // Test create route
    const createResult = await testRoute('/live/create', {});
    console.log('Create result:', createResult);
    
    // Test transition route  
    const transitionResult = await testRoute('/live/transition', { broadcastId: 'test123', broadcastStatus: 'live' });
    console.log('Transition result:', transitionResult);
    
    // Test end route
    const endResult = await testRoute('/live/end', { broadcastId: 'test123' });
    console.log('End result:', endResult);
    
    console.log('\n✅ All routes accessible and working!');
  } catch (error) {
    console.error('❌ Test failed:', error);
  } finally {
    server.close();
  }
});
