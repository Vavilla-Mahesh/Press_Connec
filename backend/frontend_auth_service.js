// Frontend Session Management for Press Connect
// This demonstrates the localStorage + backend session hybrid approach

class AuthService {
  constructor(backendBaseUrl = 'http://localhost:5000') {
    this.backendBaseUrl = backendBaseUrl;
  }

  // Encrypt data before storing in localStorage (basic encryption)
  encrypt(data) {
    return btoa(JSON.stringify(data));
  }

  // Decrypt data from localStorage
  decrypt(encryptedData) {
    try {
      return JSON.parse(atob(encryptedData));
    } catch {
      return null;
    }
  }

  // Store session in localStorage
  storeSession(sessionData) {
    const encryptedData = this.encrypt(sessionData);
    localStorage.setItem('press_connect_session', encryptedData);
  }

  // Get session from localStorage
  getStoredSession() {
    const encryptedData = localStorage.getItem('press_connect_session');
    if (!encryptedData) return null;
    return this.decrypt(encryptedData);
  }

  // Clear session from localStorage
  clearSession() {
    localStorage.removeItem('press_connect_session');
  }

  // Login function
  async login(username, password) {
    try {
      const response = await fetch(`${this.backendBaseUrl}/auth/app-login`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ username, password })
      });

      const data = await response.json();

      if (response.ok) {
        // Store session in localStorage
        const sessionData = {
          currentUser: data.user.username,
          sessionId: data.session.sessionId,
          isLoggedIn: true,
          lastActivity: new Date().toISOString(),
          associatedAdmin: data.user.associatedWith,
          token: data.token,
          expiresAt: data.session.expiresAt
        };

        this.storeSession(sessionData);
        return { success: true, user: data.user, requiresYouTubeAuth: !data.user.associatedWith };
      } else {
        return { success: false, error: data.error };
      }
    } catch (error) {
      return { success: false, error: 'Network error' };
    }
  }

  // Validate current session
  async validateSession() {
    const session = this.getStoredSession();
    if (!session) {
      return { valid: false, error: 'No stored session' };
    }

    // Check if session is expired locally
    if (new Date(session.expiresAt) < new Date()) {
      this.clearSession();
      return { valid: false, error: 'Session expired' };
    }

    try {
      const response = await fetch(`${this.backendBaseUrl}/auth/validate-session`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ sessionId: session.sessionId })
      });

      const data = await response.json();

      if (response.ok && data.valid) {
        // Update last activity
        session.lastActivity = new Date().toISOString();
        this.storeSession(session);
        return { 
          valid: true, 
          user: data.user, 
          hasYouTubeAuth: data.hasYouTubeAuth,
          requiresYouTubeAuth: data.requiresYouTubeAuth
        };
      } else {
        this.clearSession();
        return { valid: false, error: data.error || 'Session invalid' };
      }
    } catch (error) {
      return { valid: false, error: 'Network error' };
    }
  }

  // App startup initialization
  async initializeApp() {
    console.log('Initializing Press Connect app...');

    const sessionValidation = await this.validateSession();

    if (sessionValidation.valid) {
      console.log('Valid session found for user:', sessionValidation.user.username);
      
      if (sessionValidation.hasYouTubeAuth) {
        console.log('YouTube authentication available. Redirecting to Go Live page...');
        return { action: 'navigate', page: 'go-live', user: sessionValidation.user };
      } else if (!sessionValidation.requiresYouTubeAuth) {
        console.log('User is associated. Using shared YouTube authentication...');
        return { action: 'navigate', page: 'go-live', user: sessionValidation.user };
      } else {
        console.log('YouTube authentication required...');
        return { action: 'navigate', page: 'youtube-auth', user: sessionValidation.user };
      }
    } else {
      console.log('No valid session. Showing login screen...');
      return { action: 'navigate', page: 'login', error: sessionValidation.error };
    }
  }

  // Logout
  async logout() {
    const session = this.getStoredSession();
    
    if (session && session.token) {
      try {
        await fetch(`${this.backendBaseUrl}/auth/logout`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${session.token}`
          }
        });
      } catch (error) {
        console.error('Logout error:', error);
      }
    }

    this.clearSession();
    return { success: true };
  }

  // Get current user
  getCurrentUser() {
    const session = this.getStoredSession();
    return session ? {
      username: session.currentUser,
      associatedWith: session.associatedAdmin,
      isLoggedIn: session.isLoggedIn
    } : null;
  }

  // Get auth token for API calls
  getAuthToken() {
    const session = this.getStoredSession();
    return session ? session.token : null;
  }
}

// Usage example:
/*
const authService = new AuthService();

// App startup
authService.initializeApp().then(result => {
  switch (result.action) {
    case 'navigate':
      switch (result.page) {
        case 'login':
          showLoginPage();
          break;
        case 'youtube-auth':
          showYouTubeAuthPage(result.user);
          break;
        case 'go-live':
          showGoLivePage(result.user);
          break;
      }
      break;
  }
});

// Login
authService.login('moderator', '5678').then(result => {
  if (result.success) {
    if (result.requiresYouTubeAuth) {
      showYouTubeAuthPage(result.user);
    } else {
      showGoLivePage(result.user);
    }
  } else {
    showError(result.error);
  }
});
*/

// Export for use in modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = AuthService;
}