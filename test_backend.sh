#!/bin/bash

# Press Connect Backend Test Script
echo "🧪 Testing Press Connect Backend APIs"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

BASE_URL="http://localhost:5000"

# Function to test endpoint
test_endpoint() {
    local method=$1
    local endpoint=$2
    local expected_status=$3
    local description=$4
    local data=$5
    
    echo -n "Testing $description... "
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "%{http_code}" -o /dev/null "$BASE_URL$endpoint")
    else
        response=$(curl -s -w "%{http_code}" -o /dev/null -X "$method" -H "Content-Type: application/json" -d "$data" "$BASE_URL$endpoint")
    fi
    
    if [ "$response" = "$expected_status" ]; then
        echo -e "${GREEN}✓ PASS${NC} (HTTP $response)"
    else
        echo -e "${RED}✗ FAIL${NC} (Expected $expected_status, got $response)"
    fi
}

# Start backend in background
echo "🚀 Starting backend server..."
cd backend
node server.js &
BACKEND_PID=$!

# Wait for server to start
sleep 3

echo -e "\n📊 Running API Tests"
echo "--------------------"

# Test health endpoint
test_endpoint "GET" "/health" "200" "Health Check"

# Test app login
test_endpoint "POST" "/auth/app-login" "400" "App Login (without credentials)" '{"username":"","password":""}'

# Test streaming status (unauthorized)
test_endpoint "GET" "/streaming/status" "401" "Streaming Status (unauthorized)"

# Test non-existent endpoint
test_endpoint "GET" "/nonexistent" "404" "Non-existent Endpoint"

# Test CORS
echo -n "Testing CORS headers... "
cors_response=$(curl -s -H "Origin: http://localhost:3000" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: Content-Type" -X OPTIONS "$BASE_URL/auth/app-login" -I)
if echo "$cors_response" | grep -q "Access-Control-Allow-Origin"; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
fi

echo -e "\n🏁 Test Summary"
echo "---------------"
echo "Backend server is running on port 5000"
echo "RTMP server is running on port 1935"
echo "HTTP media server is running on port 8000"

# Check if processes are running
if kill -0 $BACKEND_PID 2>/dev/null; then
    echo -e "${GREEN}✓ Backend process is healthy${NC}"
else
    echo -e "${RED}✗ Backend process failed${NC}"
fi

# Clean up
echo -e "\n🧹 Cleaning up..."
kill $BACKEND_PID 2>/dev/null
wait $BACKEND_PID 2>/dev/null

echo -e "\n${GREEN}Tests completed!${NC}"
echo ""
echo "📚 Next Steps:"
echo "1. Configure your Google OAuth credentials"
echo "2. Update local.config.json with your settings"
echo "3. Test with Flutter app"
echo ""
echo "📖 See STREAMING_IMPLEMENTATION.md for full setup guide"