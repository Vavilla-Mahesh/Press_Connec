# Press Connect Authentication System

A comprehensive authentication system with YouTube OAuth integration, session persistence, and token sharing between associated users.

## Features

- ✅ **User Association System**: Admin users can share YouTube tokens with associated members
- ✅ **PostgreSQL Integration**: Secure encrypted token storage and session management
- ✅ **Hybrid Session Persistence**: localStorage + PostgreSQL for optimal performance
- ✅ **Automatic Token Refresh**: Background system refreshes expired tokens
- ✅ **Session Validation**: Validates sessions across app restarts
- ✅ **Password Security**: Bcrypt hashing for secure password storage

## User Types

### Admin Users (`associatedWith: null`)
- Must complete YouTube OAuth authentication
- Tokens stored in PostgreSQL with encryption
- Associated members inherit their tokens

### Associated Members (`associatedWith: "admin_username"`)
- Skip YouTube OAuth (use admin's tokens)
- Full access to live streaming features
- Sessions tracked independently

### Independent Users (`associatedWith: null`)
- Must complete their own YouTube OAuth
- Store and manage their own tokens
- Operate independently

## Database Schema

```sql
-- Users table
CREATE TABLE users (
  username VARCHAR(50) PRIMARY KEY,
  password_hash VARCHAR(255) NOT NULL,
  associated_with VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (associated_with) REFERENCES users(username)
);

-- User sessions table  
CREATE TABLE user_sessions (
  session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username VARCHAR(50) NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP + INTERVAL '30 days'),
  FOREIGN KEY (username) REFERENCES users(username) ON DELETE CASCADE
);

-- YouTube OAuth tokens (encrypted storage)
CREATE TABLE youtube_tokens (
  username VARCHAR(50) PRIMARY KEY,
  access_token TEXT NOT NULL, -- Encrypted with pgcrypto
  refresh_token TEXT NOT NULL, -- Encrypted with pgcrypto  
  token_type VARCHAR(20) DEFAULT 'Bearer',
  expires_at TIMESTAMP NOT NULL,
  scope TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (username) REFERENCES users(username) ON DELETE CASCADE
);
```

## Configuration

### backend/local.config.json
```json
{
  "appLogin": [
    { 
      "username": "admin", 
      "password": "1234",
      "associatedWith": null
    },
    { 
      "username": "moderator", 
      "password": "5678",
      "associatedWith": "admin"
    },
    { 
      "username": "user1", 
      "password": "9012",
      "associatedWith": "admin"
    },
    { 
      "username": "user2", 
      "password": "3456",
      "associatedWith": null
    }
  ],
  "oauth": {
    "clientId": "your_youtube_oauth_client_id",
    "clientSecret": "your_youtube_oauth_client_secret",
    "redirectUri": "com.example.press_connect:/oauth2redirect"
  },
  "jwt": {
    "secret": "your_jwt_secret_key_here",
    "expiresIn": "30d"
  },
  "database": {
    "host": "localhost",
    "port": 5432,
    "database": "press_connect_db",
    "user": "press_connect_user",
    "password": "press_connect_pass",
    "ssl": false
  },
  "encryption": {
    "key": "your_32_character_encryption_key_here"
  }
}
```

### Environment Variables (.env)
```env
# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=press_connect_db
DB_USER=press_connect_user
DB_PASSWORD=press_connect_pass
DB_SSL=false

# Encryption Key (32 characters)
ENCRYPTION_KEY=your_32_character_encryption_key_here

# JWT Secret
JWT_SECRET=your_jwt_secret_key_here

# YouTube OAuth (optional - overrides local.config.json)
GOOGLE_CLIENT_ID=your_youtube_oauth_client_id
GOOGLE_CLIENT_SECRET=your_youtube_oauth_client_secret

# Backend Base URL
BACKEND_BASE_URL=http://localhost:5000
```

## Setup Instructions

### 1. Database Setup
```bash
# Install PostgreSQL
sudo apt-get install postgresql postgresql-contrib

# Create database and user
sudo -u postgres psql
CREATE DATABASE press_connect_db;
CREATE USER press_connect_user WITH PASSWORD 'press_connect_pass';
GRANT ALL PRIVILEGES ON DATABASE press_connect_db TO press_connect_user;
```

### 2. Backend Setup
```bash
cd backend
npm install
cp .env.example .env
# Edit .env with your configuration
npm start
```

### 3. Test Authentication (Without Database)
```bash
# Test password hashing and JWT logic
node test_auth.js

# Test complete authentication flow with mock database
node test_complete_flow.js
```

## API Endpoints

### Authentication
- `POST /auth/app-login` - User login
- `POST /auth/validate-session` - Validate stored session
- `POST /auth/logout` - Logout and deactivate session
- `POST /auth/exchange` - Exchange YouTube OAuth code for tokens

### Live Streaming
- `POST /live/create` - Create YouTube live stream
- `POST /live/end` - End live stream

### Health Check
- `GET /health` - Server health status

## Authentication Flow

### 1. App Startup
```javascript
// Check localStorage for session
const session = localStorage.getItem('press_connect_session');

if (session) {
  // Validate session with backend
  const validation = await fetch('/auth/validate-session', {
    method: 'POST',
    body: JSON.stringify({ sessionId: session.sessionId })
  });
  
  if (validation.valid && validation.hasYouTubeAuth) {
    // Navigate directly to Go Live page
    navigateToGoLive();
  }
}
```

### 2. User Login
```javascript
const loginResult = await fetch('/auth/app-login', {
  method: 'POST',
  body: JSON.stringify({ username, password })
});

if (loginResult.success) {
  // Store session in localStorage
  localStorage.setItem('press_connect_session', JSON.stringify({
    currentUser: loginResult.user.username,
    sessionId: loginResult.session.sessionId,
    isLoggedIn: true,
    lastActivity: new Date().toISOString(),
    associatedAdmin: loginResult.user.associatedWith
  }));
  
  if (loginResult.user.associatedWith) {
    // Associated user - skip YouTube OAuth
    navigateToGoLive();
  } else {
    // Admin/Independent user - require YouTube OAuth
    navigateToYouTubeAuth();
  }
}
```

### 3. Token Management
- **Admin users**: Store encrypted tokens in PostgreSQL after YouTube OAuth
- **Associated users**: Automatically retrieve admin's tokens when needed
- **Independent users**: Store their own encrypted tokens
- **Background refresh**: System automatically refreshes tokens before expiry

## Frontend Integration

See `frontend_auth_service.js` for a complete frontend authentication service that handles:
- localStorage session management
- Session validation
- App startup logic
- Login/logout flows
- Token management

## Security Features

- **Password Hashing**: Bcrypt with salt rounds
- **Token Encryption**: PostgreSQL pgcrypto for YouTube tokens
- **Session Management**: UUID-based sessions with expiration
- **JWT Security**: Signed tokens with configurable expiration
- **SQL Injection Protection**: Parameterized queries
- **Session Validation**: Both localStorage and database validation

## Testing

The system includes comprehensive tests:
- `test_auth.js`: Tests password hashing, user associations, and JWT tokens
- `test_complete_flow.js`: Tests complete authentication flow with mock database
- `frontend_auth_service.js`: Frontend integration example

All tests can run without requiring PostgreSQL setup, using mock implementations.

## Production Deployment

1. Set up PostgreSQL with SSL
2. Configure environment variables
3. Generate secure encryption keys (32+ characters)
4. Set up YouTube OAuth credentials in Google Cloud Console
5. Enable HTTPS for frontend-backend communication
6. Configure secure CORS settings

## Token Refresh System

The backend automatically runs a token refresh system every 5 minutes:
- Finds tokens expiring within 5 minutes
- Refreshes using YouTube OAuth refresh endpoint
- Updates encrypted tokens in PostgreSQL
- Handles refresh failures gracefully
- For admin tokens, automatically benefits all associated users