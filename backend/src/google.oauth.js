const { google } = require('googleapis');

const exchangeCodeForTokens = async (serverAuthCode, oauthConfig) => {
  try {
    // For Android OAuth, client secret is not required and should not be used
    // This follows OAuth 2.0 best practices for public clients (mobile apps)
    const oauth2Client = new google.auth.OAuth2(
      oauthConfig.clientId,
      oauthConfig.clientSecret || null, // Allow null/undefined for Android apps
      oauthConfig.redirectUri
    );

    const { tokens } = await oauth2Client.getToken(serverAuthCode);
    
    if (!tokens.access_token) {
      throw new Error('No access token received');
    }

    return {
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      expires_in: tokens.expiry_date,
      token_type: 'Bearer'
    };

  } catch (error) {
    console.error('OAuth token exchange error:', error);
    return null;
  }
};

const refreshAccessToken = async (refreshToken, oauthConfig) => {
  try {
    // For Android OAuth, client secret is not required and should not be used
    const oauth2Client = new google.auth.OAuth2(
      oauthConfig.clientId,
      oauthConfig.clientSecret || null, // Allow null/undefined for Android apps
      oauthConfig.redirectUri
    );

    oauth2Client.setCredentials({
      refresh_token: refreshToken
    });

    const { credentials } = await oauth2Client.refreshAccessToken();
    
    return {
      access_token: credentials.access_token,
      expires_in: credentials.expiry_date,
      token_type: 'Bearer'
    };

  } catch (error) {
    console.error('Token refresh error:', error);
    return null;
  }
};

const getYouTubeAPI = (accessToken) => {
  const oauth2Client = new google.auth.OAuth2();
  oauth2Client.setCredentials({
    access_token: accessToken
  });

  return google.youtube({
    version: 'v3',
    auth: oauth2Client
  });
};

module.exports = {
  exchangeCodeForTokens,
  refreshAccessToken,
  getYouTubeAPI
};