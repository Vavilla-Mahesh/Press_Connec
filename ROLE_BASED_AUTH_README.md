# Press Connect - Role-Based Authentication System

## Overview

This implementation provides a two-step login system with role-based authentication for the Press Connect live streaming application. The system supports Admin and User roles with different authentication flows and features.

## Architecture

### Authentication Flow

#### Admin Users
1. **Login 1**: Username/Password authentication
2. **Login 2**: YouTube OAuth authentication
3. **Access**: Full application access + User Management

#### Regular Users
1. **Login 1**: Username/Password authentication (created by Admin)
2. **Access**: Direct access to Go Live functionality using Admin's YouTube OAuth

### Database Schema

```sql
-- Users table with role support
users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(50) NOT NULL DEFAULT 'user',
  admin_id INTEGER REFERENCES users(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- OAuth tokens (one per admin)
oauth_tokens (
  id SERIAL PRIMARY KEY,
  admin_id INTEGER UNIQUE NOT NULL REFERENCES users(id),
  access_token TEXT NOT NULL,
  refresh_token TEXT,
  expires_at BIGINT,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Session management
sessions (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  token TEXT NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## Setup Instructions

### Prerequisites

- Node.js 14+ with npm
- PostgreSQL 12+ (optional - file-based fallback available)
- Flutter 3.0+ for mobile app

### Backend Setup

1. **Install Dependencies**
   ```bash
   cd backend
   npm install
   ```

2. **Configure Database (Optional)**
   ```bash
   # Create PostgreSQL database
   createdb press_connect
   
   # Set environment variables
   export DB_HOST=localhost
   export DB_USER=your_db_user
   export DB_PASSWORD=your_db_password
   export DB_NAME=press_connect
   ```

3. **Configure Application**
   
   Create `backend/local.config.json`:
   ```json
   {
     "appLogin": [
       { 
         "username": "admin", 
         "password": "your_secure_admin_password" 
       }
     ],
     "oauth": {
       "clientId": "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com",
       "redirectUri": "com.example.press_connect:/oauth2redirect"
     },
     "jwt": {
       "secret": "your-super-secret-jwt-key-min-32-characters",
       "expiresIn": "24h"
     }
   }
   ```

4. **Start Backend**
   ```bash
   node server.js
   ```

### Mobile App Setup

1. **Install Dependencies**
   ```bash
   cd press_connect
   flutter pub get
   ```

2. **Configure App**
   
   Update `press_connect/assets/config.json`:
   ```json
   {
     "backendBaseUrl": "http://your-backend-url:5000",
     "googleClientId": "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com",
     "youtubeScopes": [
       "https://www.googleapis.com/auth/youtube",
       "https://www.googleapis.com/auth/youtube.upload"
     ]
   }
   ```

3. **Run App**
   ```bash
   flutter run
   ```

## API Endpoints

### Authentication
- `POST /auth/app-login` - Login with username/password
- `POST /auth/exchange` - Exchange YouTube OAuth code (admin only)

### User Management (Admin Only)
- `POST /users` - Create new user
- `GET /users` - List all users under admin
- `PUT /users/:userId` - Update user password
- `DELETE /users/:userId` - Delete user

### Live Streaming
- `POST /live/create` - Create live stream (uses admin's OAuth for regular users)
- `POST /live/end` - End live stream

## Features

### Backend Features

1. **Role-Based Authentication**
   - JWT tokens with role information
   - Admin/User role distinction
   - Automatic role-based access control

2. **Database Support**
   - PostgreSQL primary storage
   - File-based fallback for development
   - Automatic table creation and migrations

3. **User Management**
   - Complete CRUD operations for admin users
   - Password hashing with bcrypt
   - User-Admin relationship mapping

4. **Token Management**
   - Enhanced token storage system
   - Admin OAuth tokens shared with their users
   - Automatic token refresh handling

### Mobile App Features

1. **Smart Navigation**
   - Automatic routing based on role and auth state
   - Session persistence across app restarts
   - Role-aware UI components

2. **User Management Interface**
   - Admin can create, edit, and delete users
   - Password management for users
   - Real-time user list updates

3. **Enhanced Authentication**
   - Role-based login flows
   - Secure token storage
   - Automatic error handling

## Security Features

1. **Password Security**
   - bcrypt hashing with salt rounds
   - Minimum password requirements
   - Secure storage

2. **Token Security**
   - JWT with expiration
   - Role-based claims
   - Secure HTTP headers

3. **Access Control**
   - Route-level protection
   - Role-based middleware
   - Admin-only endpoints

## Development Notes

### Database Fallback
The system automatically falls back to file-based storage if PostgreSQL is not available, making development easier without requiring database setup.

### Environment Variables
For production deployment, use environment variables:
```bash
export APP_USERNAME=admin
export APP_PASSWORD=secure_password
export GOOGLE_CLIENT_ID=your_client_id
export JWT_SECRET=your_jwt_secret
export DB_HOST=your_db_host
export DB_USER=your_db_user
export DB_PASSWORD=your_db_password
export DB_NAME=your_db_name
export PORT=5000
```

### Testing
The backend includes comprehensive error handling and logging for debugging authentication flows and database operations.

## Usage Examples

### Admin Workflow
1. Admin logs in with username/password
2. Admin performs YouTube OAuth authentication
3. Admin creates users through the management interface
4. Admin can stream live using their YouTube account
5. Users created by admin can stream using the admin's YouTube OAuth

### User Workflow
1. User logs in with credentials provided by admin
2. User is directly taken to Go Live screen
3. User can start streaming immediately using admin's YouTube OAuth
4. No additional authentication required

## Troubleshooting

### Common Issues

1. **Database Connection Failed**
   - Check PostgreSQL service is running
   - Verify connection credentials
   - System will fallback to file-based storage

2. **YouTube OAuth Issues**
   - Verify Google Cloud Console configuration
   - Check client ID and redirect URI
   - Ensure YouTube Data API v3 is enabled

3. **Token Expiration**
   - System automatically handles token refresh
   - Check refresh token availability
   - Re-authentication may be required for expired refresh tokens

### Logs
- Backend logs all authentication attempts
- Database connection status is logged on startup
- API endpoints and their access levels are displayed on startup

## Production Deployment

1. **Security Hardening**
   - Use strong JWT secrets
   - Enable HTTPS
   - Use environment variables for all secrets
   - Configure proper CORS policies

2. **Database Setup**
   - Use managed PostgreSQL service
   - Configure connection pooling
   - Set up regular backups

3. **Monitoring**
   - Monitor authentication failures
   - Track user creation/deletion events
   - Monitor YouTube API quota usage