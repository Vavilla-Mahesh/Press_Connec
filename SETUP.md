# Configuration Setup

## Frontend Configuration

Copy `assets/config.json` and update the following values:

- `backendBaseUrl`: Your backend server URL (e.g., `https://your-app.herokuapp.com`)
- `googleClientId`: Your Google OAuth2 client ID

## Backend Configuration

Copy `backend/local.config.json` and update:

- `jwt.secret`: A secure JWT secret key (use a random 32+ character string)
- `oauth.clientId`: Your Google OAuth2 client ID (same as frontend)
- `oauth.clientSecret`: Your Google OAuth2 client secret
- `oauth.redirectUri`: Usually `urn:ietf:wg:oauth:2.0:oob` for mobile apps

## Environment Variables

Create a `.env` file in the backend directory:

```
PORT=5000
NODE_ENV=development
BACKEND_BASE_URL=http://localhost:5000
```

## Google Cloud Console Setup

1. Create a project in Google Cloud Console
2. Enable YouTube Data API v3
3. Create OAuth2 credentials (Web application type)
4. Add authorized origins and redirect URIs
5. Download the client configuration

## YouTube Channel Requirements

- YouTube channel must be verified
- Live streaming must be enabled
- Channel must not have live streaming restrictions in the past 90 days

## Production Deployment

- Use HTTPS for both frontend and backend
- Set secure JWT secrets
- Configure proper CORS origins
- Use environment variables instead of config files for secrets