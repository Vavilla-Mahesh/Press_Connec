const request = require('supertest');
const express = require('express');
const jwt = require('jsonwebtoken');

// Mock the live controller
const liveController = {
  createLiveStream: jest.fn(),
  startLiveStream: jest.fn(),
  endLiveStream: jest.fn()
};

const app = express();
app.use(express.json());

// Mock JWT verification middleware
const verifyToken = (req, res, next) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  
  if (!token) {
    return res.status(401).json({ error: 'No token provided' });
  }

  try {
    req.user = { username: 'testuser' };
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
};

// Routes
app.post('/live/create', verifyToken, liveController.createLiveStream);
app.post('/live/start', verifyToken, liveController.startLiveStream);
app.post('/live/end', verifyToken, liveController.endLiveStream);

describe('Live Streaming API', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('POST /live/create', () => {
    it('should require authentication', async () => {
      const response = await request(app)
        .post('/live/create')
        .send({});

      expect(response.status).toBe(401);
      expect(response.body.error).toBe('No token provided');
    });

    it('should call createLiveStream with valid token', async () => {
      liveController.createLiveStream.mockImplementation((req, res) => {
        res.json({ success: true, broadcastId: 'test-id' });
      });

      const response = await request(app)
        .post('/live/create')
        .set('Authorization', 'Bearer valid-token')
        .send({});

      expect(response.status).toBe(200);
      expect(liveController.createLiveStream).toHaveBeenCalled();
    });
  });

  describe('POST /live/start', () => {
    it('should require authentication', async () => {
      const response = await request(app)
        .post('/live/start')
        .send({ broadcastId: 'test-id' });

      expect(response.status).toBe(401);
    });

    it('should call startLiveStream with valid token and broadcastId', async () => {
      liveController.startLiveStream.mockImplementation((req, res) => {
        res.json({ success: true, message: 'Live stream started successfully' });
      });

      const response = await request(app)
        .post('/live/start')
        .set('Authorization', 'Bearer valid-token')
        .send({ broadcastId: 'test-broadcast-id' });

      expect(response.status).toBe(200);
      expect(liveController.startLiveStream).toHaveBeenCalled();
    });
  });

  describe('POST /live/end', () => {
    it('should require authentication', async () => {
      const response = await request(app)
        .post('/live/end')
        .send({ broadcastId: 'test-id' });

      expect(response.status).toBe(401);
    });

    it('should call endLiveStream with valid token and broadcastId', async () => {
      liveController.endLiveStream.mockImplementation((req, res) => {
        res.json({ success: true, message: 'Live stream ended successfully' });
      });

      const response = await request(app)
        .post('/live/end')
        .set('Authorization', 'Bearer valid-token')
        .send({ broadcastId: 'test-broadcast-id' });

      expect(response.status).toBe(200);
      expect(liveController.endLiveStream).toHaveBeenCalled();
    });
  });
});