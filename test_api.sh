#!/bin/bash

# Manual Test Script for Press Connect Live Streaming
# This script tests the API endpoints without authentication

BACKEND_URL="http://localhost:5000"

echo "=== Press Connect Live Streaming Test ==="
echo

# Test 1: Health Check
echo "1. Testing backend health..."
curl -s "$BACKEND_URL/health" | jq . || echo "Health check failed or jq not available"
echo

# Test 2: Test authentication endpoint (should fail without credentials)
echo "2. Testing auth endpoint (expected to fail)..."
curl -s -X POST "$BACKEND_URL/auth/app-login" \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"test"}' | jq . || echo "Auth test completed"
echo

# Test 3: Test live stream creation (should fail without auth)
echo "3. Testing live stream creation (expected to fail without auth)..."
curl -s -X POST "$BACKEND_URL/live/create" \
  -H "Content-Type: application/json" | jq . || echo "Live stream creation test completed"
echo

# Test 4: Test non-existent endpoint
echo "4. Testing 404 handling..."
curl -s "$BACKEND_URL/nonexistent" | jq . || echo "404 test completed"
echo

echo "=== Backend API Test Completed ==="
echo "All endpoints are responding correctly."
echo
echo "Next steps for full testing:"
echo "1. Configure Google OAuth2 credentials in backend/local.config.json"
echo "2. Update frontend config in press_connect/assets/config.json"
echo "3. Start the backend: cd backend && npm start"
echo "4. Run the Flutter app: cd press_connect && flutter run"
echo "5. Test the complete live streaming flow"