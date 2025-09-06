const database = require('./database');
const fs = require('fs').promises;
const path = require('path');

const TOKENS_FILE = path.join(__dirname, '..', 'tokens.json');

// File-based storage functions (fallback)
const initializeTokensFile = async () => {
  try {
    await fs.access(TOKENS_FILE);
  } catch (error) {
    await fs.writeFile(TOKENS_FILE, JSON.stringify({}));
  }
};

const loadTokensFromFile = async () => {
  try {
    await initializeTokensFile();
    const data = await fs.readFile(TOKENS_FILE, 'utf8');
    return JSON.parse(data);
  } catch (error) {
    console.error('Error loading tokens from file:', error);
    return {};
  }
};

const saveTokensToFile = async (tokens) => {
  try {
    await fs.writeFile(TOKENS_FILE, JSON.stringify(tokens, null, 2));
  } catch (error) {
    console.error('Error saving tokens to file:', error);
  }
};

const storeTokensInDB = async (adminId, tokens) => {
  const query = `
    INSERT INTO oauth_tokens (admin_id, access_token, refresh_token, expires_at, updated_at)
    VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
    ON CONFLICT (admin_id) 
    DO UPDATE SET 
      access_token = EXCLUDED.access_token,
      refresh_token = EXCLUDED.refresh_token,
      expires_at = EXCLUDED.expires_at,
      updated_at = CURRENT_TIMESTAMP;
  `;

  await database.query(query, [
    adminId,
    tokens.access_token,
    tokens.refresh_token || null,
    tokens.expires_in || null
  ]);
};

const getTokensFromDB = async (adminId) => {
  const query = `
    SELECT access_token, refresh_token, expires_at
    FROM oauth_tokens 
    WHERE admin_id = $1;
  `;
  
  const result = await database.query(query, [adminId]);
  
  if (result.rows.length === 0) {
    return null;
  }

  const row = result.rows[0];
  return {
    access_token: row.access_token,
    refresh_token: row.refresh_token,
    expires_in: row.expires_at,
    token_type: 'Bearer'
  };
};

const deleteTokensFromDB = async (adminId) => {
  const query = `DELETE FROM oauth_tokens WHERE admin_id = $1;`;
  await database.query(query, [adminId]);
};

// Public interface functions
const storeTokens = async (userIdentifier, tokens) => {
  if (database.isAvailable()) {
    // For database storage, userIdentifier should be adminId (number)
    // For file storage, it's username (string) for backward compatibility
    if (typeof userIdentifier === 'number') {
      await storeTokensInDB(userIdentifier, tokens);
    } else {
      // Try to find admin ID by username for database storage
      try {
        const query = `SELECT id FROM users WHERE username = $1 AND role = 'admin';`;
        const result = await database.query(query, [userIdentifier]);
        if (result.rows.length > 0) {
          await storeTokensInDB(result.rows[0].id, tokens);
        } else {
          throw new Error('Admin user not found');
        }
      } catch (error) {
        console.error('Error storing tokens in database:', error);
        // Fallback to file storage
        const allTokens = await loadTokensFromFile();
        allTokens[userIdentifier] = {
          ...tokens,
          updated_at: new Date().toISOString()
        };
        await saveTokensToFile(allTokens);
      }
    }
  } else {
    // File-based storage (fallback)
    const allTokens = await loadTokensFromFile();
    allTokens[userIdentifier] = {
      ...tokens,
      updated_at: new Date().toISOString()
    };
    await saveTokensToFile(allTokens);
  }
};

const getTokens = async (userIdentifier) => {
  if (database.isAvailable()) {
    if (typeof userIdentifier === 'number') {
      return await getTokensFromDB(userIdentifier);
    } else {
      // Try to find admin ID by username or find the admin for this user
      try {
        let query, params;
        
        // First check if this user is an admin
        query = `SELECT id FROM users WHERE username = $1 AND role = 'admin';`;
        let result = await database.query(query, [userIdentifier]);
        
        if (result.rows.length > 0) {
          // User is admin, get their tokens
          return await getTokensFromDB(result.rows[0].id);
        } else {
          // User is not admin, find their admin's tokens
          query = `SELECT admin_id FROM users WHERE username = $1 AND role = 'user';`;
          result = await database.query(query, [userIdentifier]);
          
          if (result.rows.length > 0) {
            return await getTokensFromDB(result.rows[0].admin_id);
          } else {
            return null;
          }
        }
      } catch (error) {
        console.error('Error getting tokens from database:', error);
        // Fallback to file storage
        const allTokens = await loadTokensFromFile();
        return allTokens[userIdentifier] || null;
      }
    }
  } else {
    // File-based storage (fallback)
    const allTokens = await loadTokensFromFile();
    return allTokens[userIdentifier] || null;
  }
};

const deleteTokens = async (userIdentifier) => {
  if (database.isAvailable()) {
    if (typeof userIdentifier === 'number') {
      await deleteTokensFromDB(userIdentifier);
    } else {
      try {
        const query = `SELECT id FROM users WHERE username = $1 AND role = 'admin';`;
        const result = await database.query(query, [userIdentifier]);
        if (result.rows.length > 0) {
          await deleteTokensFromDB(result.rows[0].id);
        }
      } catch (error) {
        console.error('Error deleting tokens from database:', error);
        // Fallback to file storage
        const allTokens = await loadTokensFromFile();
        delete allTokens[userIdentifier];
        await saveTokensToFile(allTokens);
      }
    }
  } else {
    // File-based storage (fallback)
    const allTokens = await loadTokensFromFile();
    delete allTokens[userIdentifier];
    await saveTokensToFile(allTokens);
  }
};

const isTokenExpired = (tokens) => {
  if (!tokens || !tokens.expires_in) {
    return true;
  }
  
  const now = Date.now();
  const expiryTime = new Date(tokens.expires_in).getTime();
  
  // Consider token expired if it expires within the next 5 minutes
  return (expiryTime - now) < (5 * 60 * 1000);
};

module.exports = {
  storeTokens,
  getTokens,
  deleteTokens,
  isTokenExpired
};