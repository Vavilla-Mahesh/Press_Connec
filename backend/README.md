# Press Connect Backend

Node.js/Express backend API for the Press Connect live streaming application with PostgreSQL database and admin user management.

## Features

- **Database-driven authentication** with PostgreSQL
- **Admin user management** with role-based access control
- **JWT token authentication** with session management
- **Encrypted OAuth token storage** for YouTube integration
- **RESTful API** with comprehensive error handling
- **Production-ready** logging and monitoring

## Quick Start

### Prerequisites

- Node.js 16+
- PostgreSQL 12+
- npm or yarn

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd backend

# Install dependencies
npm install

# Copy example configuration
cp local.config.json.example local.config.json

# Edit configuration with your settings
nano local.config.json
```

### Configuration

Create `local.config.json` with your settings:

```json
{
  "appLogin": [
    {
      "username": "admin",
      "password": "your_secure_password",
      "associatedWith": null
    }
  ],
  "oauth": {
    "clientId": "your_google_client_id.apps.googleusercontent.com",
    "redirectUri": "com.example.press_connect:/oauth2redirect"
  },
  "jwt": {
    "secret": "your_jwt_secret_32_characters_long",
    "expiresIn": "24h"
  },
  "database": {
    "host": "localhost",
    "port": 5432,
    "database": "press_connect_db",
    "user": "your_db_user",
    "password": "your_db_password",
    "ssl": false
  },
  "encryption": {
    "key": "your_32_character_encryption_key"
  }
}
```

### Database Setup

```bash
# Create PostgreSQL database
createdb press_connect_db

# The application will automatically create tables on startup
```

### Running the Application

```bash
# Development mode (with auto-reload)
npm run dev

# Production mode
npm start
```

The server will start on port 5000 (or the port specified in the PORT environment variable).

## API Documentation

### Authentication Endpoints

#### POST /auth/app-login
Authenticate user with username/password.

**Request:**
```json
{
  "username": "admin",
  "password": "password123"
}
```

**Response:**
```json
{
  "success": true,
  "token": "jwt_token_here",
  "user": {
    "username": "admin",
    "associatedWith": null
  },
  "session": {
    "sessionId": "session_uuid",
    "expiresAt": "2024-01-01T00:00:00.000Z"
  }
}
```

#### POST /auth/validate-session
Validate user session.

**Request:**
```json
{
  "sessionId": "session_uuid"
}
```

#### POST /auth/logout
Logout user and deactivate session.

**Headers:**
```
Authorization: Bearer <jwt_token>
```

#### POST /auth/exchange
Exchange OAuth server auth code for YouTube tokens.

**Headers:**
```
Authorization: Bearer <jwt_token>
```

**Request:**
```json
{
  "serverAuthCode": "oauth_server_auth_code"
}
```

### Admin Endpoints (Admin Only)

#### POST /admin/users
Create a new user.

**Headers:**
```
Authorization: Bearer <jwt_token>
```

**Request:**
```json
{
  "username": "newuser",
  "password": "secure_password",
  "associatedWith": "admin"
}
```

#### GET /admin/users
Get all users.

**Headers:**
```
Authorization: Bearer <jwt_token>
```

**Response:**
```json
{
  "success": true,
  "users": [
    {
      "username": "admin",
      "associated_with": null,
      "created_at": "2024-01-01T00:00:00.000Z",
      "active_sessions": 1
    }
  ]
}
```

#### PUT /admin/users/:username
Update user.

**Headers:**
```
Authorization: Bearer <jwt_token>
```

**Request:**
```json
{
  "password": "new_password",
  "associatedWith": "admin"
}
```

#### DELETE /admin/users/:username
Delete user.

**Headers:**
```
Authorization: Bearer <jwt_token>
```

#### GET /admin/stats
Get user statistics.

**Headers:**
```
Authorization: Bearer <jwt_token>
```

**Response:**
```json
{
  "success": true,
  "stats": {
    "total_users": 5,
    "admin_users": 2,
    "regular_users": 3,
    "active_sessions": 3,
    "users_with_youtube_auth": 2
  }
}
```

### Live Streaming Endpoints

#### POST /live/create
Create YouTube live stream.

**Headers:**
```
Authorization: Bearer <jwt_token>
```

#### POST /live/end
End YouTube live stream.

**Headers:**
```
Authorization: Bearer <jwt_token>
```

### Utility Endpoints

#### GET /health
Health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "version": "1.0.0"
}
```

## Database Schema

### Users Table
```sql
CREATE TABLE users (
  username VARCHAR(50) PRIMARY KEY,
  password_hash VARCHAR(255) NOT NULL,
  associated_with VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (associated_with) REFERENCES users(username)
);
```

### User Sessions Table
```sql
CREATE TABLE user_sessions (
  session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username VARCHAR(50) NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP + INTERVAL '30 days'),
  FOREIGN KEY (username) REFERENCES users(username) ON DELETE CASCADE
);
```

### YouTube Tokens Table
```sql
CREATE TABLE youtube_tokens (
  username VARCHAR(50) PRIMARY KEY,
  access_token TEXT NOT NULL,
  refresh_token TEXT NOT NULL,
  token_type VARCHAR(20) DEFAULT 'Bearer',
  expires_at TIMESTAMP NOT NULL,
  scope TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (username) REFERENCES users(username) ON DELETE CASCADE
);
```

## Environment Variables

For production deployment, use environment variables instead of config files:

```bash
# Database Configuration
export DB_HOST=your_db_host
export DB_PORT=5432
export DB_NAME=press_connect_db
export DB_USER=your_db_user
export DB_PASSWORD=your_db_password
export DB_SSL=true

# Security
export JWT_SECRET=your_jwt_secret
export ENCRYPTION_KEY=your_32_character_encryption_key

# OAuth
export GOOGLE_CLIENT_ID=your_google_client_id
export GOOGLE_CLIENT_SECRET=your_google_client_secret

# Application
export PORT=5000
export NODE_ENV=production
export BACKEND_BASE_URL=https://your-api-domain.com
```

## Security Features

- **Password hashing** with bcrypt
- **JWT token authentication** with session management
- **Encrypted token storage** for OAuth credentials
- **Role-based access control** (admin/regular users)
- **Session expiration** and cleanup
- **SQL injection protection** with parameterized queries
- **Environment variable configuration** for production

## Error Handling

The API returns consistent error responses:

```json
{
  "error": "Error message description",
  "message": "Additional error details (in development mode)"
}
```

Common HTTP status codes:
- `200` - Success
- `201` - Created
- `400` - Bad Request
- `401` - Unauthorized
- `403` - Forbidden (Admin access required)
- `404` - Not Found
- `409` - Conflict (Resource already exists)
- `500` - Internal Server Error

## Development

### Project Structure
```
backend/
├── src/
│   ├── admin.controller.js     # Admin user management
│   ├── auth.controller.js      # Authentication
│   ├── database.js            # Database connection and schema
│   ├── google.oauth.js        # Google OAuth integration
│   ├── live.controller.js     # Live streaming endpoints
│   ├── token.store.js         # Encrypted token storage
│   └── user.manager.js        # User management utilities
├── local.config.json.example  # Configuration template
├── package.json               # Dependencies and scripts
└── server.js                  # Main application file
```

### Adding New Endpoints

1. Create controller in `src/` directory
2. Add routes in `server.js`
3. Update this documentation

### Database Migrations

The application automatically creates database schema on startup. For production:

1. Run initial setup with admin user
2. Application will create all necessary tables
3. Indexes are created for performance optimization

## Deployment

See [DEPLOYMENT.md](../DEPLOYMENT.md) for detailed deployment instructions covering:

- Docker deployment
- Cloud platform deployment (Heroku, AWS, Google Cloud)
- Database setup
- Environment configuration
- SSL/TLS setup
- Monitoring and logging

## Troubleshooting

### Common Issues

1. **Database Connection Error**
   ```
   Error: ECONNREFUSED ::1:5432
   ```
   - Check PostgreSQL is running
   - Verify connection details in config
   - Check firewall settings

2. **Authentication Errors**
   ```
   Error: Invalid credentials
   ```
   - Verify username/password in config
   - Check if user exists in database
   - Verify JWT secret configuration

3. **OAuth Errors**
   ```
   Error: Failed to exchange auth code
   ```
   - Check Google Client ID configuration
   - Verify redirect URI in Google Console
   - Check OAuth scopes

### Debugging

Enable debug logging:
```bash
DEBUG=* npm start
```

Check application logs:
```bash
# View real-time logs
tail -f app.log

# Check error logs
grep -i error app.log
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Follow existing code style
4. Add tests for new features
5. Update documentation
6. Submit a pull request

## License

MIT License - see [LICENSE](../LICENSE) file for details.