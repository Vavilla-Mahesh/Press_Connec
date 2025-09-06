# Integration Testing Guide

This guide provides step-by-step instructions for testing the complete Press Connect application integration.

## Prerequisites

- PostgreSQL 12+ running locally or remotely
- Node.js 16+ installed
- Flutter 3.10+ installed (for mobile app testing)
- Google Cloud Project with YouTube Data API v3 enabled
- Google OAuth 2.0 credentials configured

## Backend Testing

### 1. Database Setup

```bash
# Create PostgreSQL database
createdb press_connect_db

# Or using SQL
psql -c "CREATE DATABASE press_connect_db;"
```

### 2. Configuration

```bash
cd backend
cp local.config.json.example local.config.json
```

Edit `local.config.json` with your actual values:

```json
{
  "appLogin": [
    {
      "username": "admin",
      "password": "admin123",
      "associatedWith": null
    }
  ],
  "oauth": {
    "clientId": "YOUR_ACTUAL_CLIENT_ID.apps.googleusercontent.com",
    "redirectUri": "com.example.press_connect:/oauth2redirect"
  },
  "jwt": {
    "secret": "your_actual_jwt_secret_32_chars_long",
    "expiresIn": "24h"
  },
  "database": {
    "host": "localhost",
    "port": 5432,
    "database": "press_connect_db",
    "user": "postgres",
    "password": "your_db_password",
    "ssl": false
  },
  "encryption": {
    "key": "your_actual_32_char_encryption_key"
  }
}
```

### 3. Start Backend

```bash
cd backend
npm install
npm start
```

Expected output:
```
Configuration loaded successfully
OAuth Client ID: YOUR_CLIENT_ID.apps.googleusercontent.com
OAuth Client Secret: [NOT CONFIGURED - Android OAuth Mode]
PostgreSQL connected successfully
Database schema created successfully
User admin created successfully
Application initialized successfully
Press Connect Backend running on port 5000
```

### 4. Test API Endpoints

#### Health Check
```bash
curl http://localhost:5000/health
```

Expected response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00.000Z",
  "version": "1.0.0"
}
```

#### Admin Login
```bash
curl -X POST http://localhost:5000/auth/app-login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "admin123"}'
```

Expected response:
```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "username": "admin",
    "associatedWith": null
  },
  "session": {
    "sessionId": "12345678-1234-1234-1234-123456789012",
    "expiresAt": "2024-01-02T12:00:00.000Z"
  }
}
```

#### Create User (Admin Only)
```bash
# Save the token from previous response
TOKEN="your_jwt_token_here"

curl -X POST http://localhost:5000/admin/users \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "testpass123",
    "associatedWith": "admin"
  }'
```

#### Get Users List
```bash
curl -X GET http://localhost:5000/admin/users \
  -H "Authorization: Bearer $TOKEN"
```

#### Get User Statistics
```bash
curl -X GET http://localhost:5000/admin/stats \
  -H "Authorization: Bearer $TOKEN"
```

### 5. Database Verification

```bash
psql -d press_connect_db -c "
SELECT 
  username, 
  associated_with, 
  created_at 
FROM users;
"
```

Expected output:
```
 username  | associated_with |         created_at         
-----------+-----------------+----------------------------
 admin     |                 | 2024-01-01 12:00:00.000000
 testuser  | admin           | 2024-01-01 12:05:00.000000
```

## Frontend Testing

### 1. Configuration

```bash
cd press_connect
cp assets/config.json.example assets/config.json
```

Edit `assets/config.json`:

```json
{
  "backendBaseUrl": "http://localhost:5000",
  "googleClientId": "YOUR_ACTUAL_CLIENT_ID.apps.googleusercontent.com",
  "youtubeScopes": [
    "https://www.googleapis.com/auth/youtube",
    "https://www.googleapis.com/auth/youtube.readonly",
    "https://www.googleapis.com/auth/youtube.force-ssl"
  ],
  "app": {
    "name": "Press Connect",
    "version": "1.0.0"
  },
  "watermark": {
    "defaultImagePath": "assets/images/watermark.png",
    "defaultWatermarkOpacity": 0.3,
    "maxOpacity": 1.0,
    "minOpacity": 0.0
  },
  "streaming": {
    "defaultBitrate": 2500000,
    "defaultResolution": {
      "width": 1280,
      "height": 720
    }
  }
}
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Run Application

```bash
# For web (if web support is enabled)
flutter run -d chrome

# For mobile (requires Android/iOS setup)
flutter run
```

### 4. Test User Authentication

1. **Login Screen Testing:**
   - Open the app
   - Enter admin credentials (`admin` / `admin123`)
   - Verify successful login
   - Check that admin options dialog appears

2. **Admin Panel Testing:**
   - Select "Admin Panel" from the dialog
   - Verify all three tabs load correctly:
     - Overview tab shows statistics
     - Users tab lists existing users
     - Create User tab has the form

3. **User Management Testing:**
   - Create a new user through the UI
   - Verify the user appears in the users list
   - Test user deletion (not admin user)
   - Verify statistics update correctly

### 5. Test Regular User Flow

1. **Create Regular User:**
   - Use admin panel to create a regular user
   - Logout from admin account

2. **Login as Regular User:**
   - Login with regular user credentials
   - Verify no admin options appear
   - Verify redirect to YouTube connect screen

## Integration Flow Testing

### 1. Complete User Management Flow

```bash
# 1. Login as admin
curl -X POST http://localhost:5000/auth/app-login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "admin123"}'

# Save token from response
TOKEN="your_token_here"

# 2. Create regular user
curl -X POST http://localhost:5000/admin/users \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "streamer1",
    "password": "stream123",
    "associatedWith": "admin"
  }'

# 3. Login as regular user
curl -X POST http://localhost:5000/auth/app-login \
  -H "Content-Type: application/json" \
  -d '{"username": "streamer1", "password": "stream123"}'

# 4. Verify session management
USER_TOKEN="regular_user_token_here"

curl -X POST http://localhost:5000/auth/validate-session \
  -H "Content-Type: application/json" \
  -d '{"sessionId": "session_id_from_login"}'
```

### 2. Error Handling Testing

```bash
# Test invalid credentials
curl -X POST http://localhost:5000/auth/app-login \
  -H "Content-Type: application/json" \
  -d '{"username": "invalid", "password": "wrong"}'

# Expected: 401 Unauthorized

# Test unauthorized admin access
curl -X GET http://localhost:5000/admin/users \
  -H "Authorization: Bearer invalid_token"

# Expected: 401 Unauthorized

# Test regular user accessing admin endpoints
curl -X GET http://localhost:5000/admin/users \
  -H "Authorization: Bearer $USER_TOKEN"

# Expected: 403 Forbidden
```

### 3. Database Integration Testing

```bash
# Verify password hashing
psql -d press_connect_db -c "
SELECT username, length(password_hash) as hash_length 
FROM users;
"

# Verify session creation
psql -d press_connect_db -c "
SELECT username, is_active, expires_at > NOW() as valid 
FROM user_sessions 
WHERE is_active = true;
"

# Verify foreign key relationships
psql -d press_connect_db -c "
SELECT u.username, u.associated_with, s.session_id
FROM users u
LEFT JOIN user_sessions s ON u.username = s.username
WHERE s.is_active = true;
"
```

## Performance Testing

### 1. Concurrent User Testing

```bash
# Install Apache Bench (if not available)
# On Ubuntu: sudo apt-get install apache2-utils

# Test concurrent logins
ab -n 100 -c 10 -p login_data.json -T application/json \
  http://localhost:5000/auth/app-login

# Content of login_data.json:
# {"username": "admin", "password": "admin123"}
```

### 2. Database Performance

```sql
-- Check query performance
EXPLAIN ANALYZE 
SELECT * FROM users WHERE username = 'admin';

-- Check index usage
SELECT schemaname, tablename, indexname, idx_blks_hit, idx_blks_read
FROM pg_statio_user_indexes;
```

## Security Testing

### 1. JWT Token Security

```bash
# Test token expiration (wait for token to expire or modify JWT secret)
curl -X GET http://localhost:5000/admin/users \
  -H "Authorization: Bearer expired_token"

# Expected: 401 Unauthorized
```

### 2. SQL Injection Testing

```bash
# Test SQL injection in login
curl -X POST http://localhost:5000/auth/app-login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin'\'''; DROP TABLE users; --", "password": "any"}'

# Should return 401 Unauthorized, not crash the server
```

### 3. Password Security

```bash
# Verify passwords are hashed in database
psql -d press_connect_db -c "
SELECT username, password_hash LIKE '$2%' as is_bcrypt_hash 
FROM users;
"

# All should return true for is_bcrypt_hash
```

## Troubleshooting

### Common Issues

1. **Database Connection Failed**
   ```
   Error: Database initialization failed
   ```
   - Check PostgreSQL is running: `pg_isready`
   - Verify database exists: `psql -l | grep press_connect`
   - Check connection details in config

2. **JWT Token Issues**
   ```
   Error: Invalid token
   ```
   - Verify JWT secret is consistent
   - Check token hasn't expired
   - Ensure proper Authorization header format

3. **Admin Access Denied**
   ```
   Error: Admin access required
   ```
   - Verify user has `associatedWith: null`
   - Check JWT contains correct user info
   - Verify token is valid and not expired

4. **Frontend Connection Issues**
   ```
   Network error: Failed to connect
   ```
   - Verify backend is running on correct port
   - Check `backendBaseUrl` in config.json
   - Verify CORS configuration allows frontend domain

### Debug Commands

```bash
# Check backend logs
tail -f backend/app.log

# Check database connections
psql -d press_connect_db -c "
SELECT state, count(*) 
FROM pg_stat_activity 
WHERE datname = 'press_connect_db' 
GROUP BY state;
"

# Test network connectivity
curl -v http://localhost:5000/health

# Check Flutter app logs
flutter logs
```

## Production Readiness Checklist

- [ ] Database backups configured
- [ ] Environment variables set (no config files)
- [ ] SSL/HTTPS enabled
- [ ] Proper logging configured
- [ ] Health monitoring setup
- [ ] Error tracking implemented
- [ ] Performance monitoring active
- [ ] Security headers configured
- [ ] Rate limiting implemented
- [ ] Database connection pooling tuned

## Next Steps

After successful integration testing:

1. Deploy to staging environment
2. Perform user acceptance testing
3. Security audit and penetration testing
4. Performance benchmarking
5. Production deployment
6. Monitoring and alerting setup

This completes the comprehensive integration testing for the Press Connect application with database-driven authentication and admin user management.