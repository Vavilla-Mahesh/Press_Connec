# Press Connect

A professional Flutter application for YouTube Live streaming with admin user management, database-driven authentication, and production-ready architecture.

## Features

### 🎥 Live Streaming
- Real-time YouTube Live streaming
- RTMP stream management
- Stream quality control (480p, 720p, 1080p)
- Connection monitoring and auto-reconnection
- Watermark overlay support

### 👥 User Management
- Database-driven authentication (PostgreSQL)
- Admin panel for user management
- Role-based access control
- Session management with JWT tokens
- Encrypted OAuth token storage

### 🔒 Security
- Encrypted database storage
- Secure JWT authentication
- OAuth 2.0 integration with YouTube
- Environment variable configuration
- Session validation and management

### 📱 Mobile App Features
- Cross-platform Flutter application
- Responsive UI with glass morphism design
- Real-time connection status
- Stream health monitoring
- Camera switching capabilities

## Quick Start

### Prerequisites
- Flutter 3.10+ 
- PostgreSQL 12+
- Node.js 16+
- YouTube Data API v3 credentials
- Google OAuth 2.0 setup

### 1. Backend Setup

```bash
cd backend
npm install
```

Create your configuration file:
```bash
cp local.config.json.example local.config.json
# Edit local.config.json with your settings
```

Set up your database:
```bash
# Create PostgreSQL database
createdb press_connect_db

# The application will automatically create tables on first run
```

Start the backend:
```bash
npm start
# or for development
npm run dev
```

### 2. Frontend Setup

```bash
cd press_connect
flutter pub get
```

Configure the app:
```bash
# Edit assets/config.json with your backend URL and settings
```

Run the app:
```bash
flutter run
```

## Configuration

### Backend Configuration

The backend uses `local.config.json` for local development and environment variables for production:

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

### Production Environment Variables

```bash
export DB_HOST=your_db_host
export DB_NAME=press_connect_db
export DB_USER=your_db_user
export DB_PASSWORD=your_db_password
export GOOGLE_CLIENT_ID=your_google_client_id
export JWT_SECRET=your_jwt_secret
export ENCRYPTION_KEY=your_encryption_key
export PORT=5000
```

## Admin Features

### User Management
- Create new users through the admin panel
- Assign users to admin accounts
- View user statistics and session information
- Delete users (except your own admin account)

### Access Control
- Admin users (no `associatedWith` field) have full access
- Regular users are associated with an admin account
- Role-based routing and UI elements

### Database Schema
- Users table with encrypted passwords
- Session management with expiration
- Encrypted OAuth token storage
- Comprehensive indexing for performance

## API Endpoints

### Authentication
- `POST /auth/app-login` - User authentication
- `POST /auth/validate-session` - Session validation
- `POST /auth/logout` - User logout
- `POST /auth/exchange` - OAuth token exchange

### Admin (Admin Only)
- `POST /admin/users` - Create user
- `GET /admin/users` - List users
- `PUT /admin/users/:username` - Update user
- `DELETE /admin/users/:username` - Delete user
- `GET /admin/stats` - User statistics

### Live Streaming
- `POST /live/create` - Create live stream
- `POST /live/end` - End live stream

## Development

### Running Tests
```bash
# Backend tests
cd backend && npm test

# Frontend tests
cd press_connect && flutter test
```

### Building for Production
```bash
# Flutter build
cd press_connect
flutter build apk --release
# or
flutter build ios --release

# Backend deployment
cd backend
# Set production environment variables
npm start
```

## Architecture

### Backend Architecture
- Express.js REST API
- PostgreSQL database with connection pooling
- JWT-based authentication with session management
- Encrypted OAuth token storage
- Comprehensive error handling and logging

### Frontend Architecture
- Flutter with Provider state management
- Service-oriented architecture
- Secure storage for sensitive data
- Real-time connection monitoring
- Glass morphism UI design

### Security Architecture
- Database-driven user management
- Encrypted storage for sensitive data
- JWT tokens with session validation
- Role-based access control
- Environment-based configuration

## Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed deployment instructions.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues and questions:
1. Check the troubleshooting section in [CONFIGURATION.md](CONFIGURATION.md)
2. Review the API documentation
3. Open an issue on GitHub
