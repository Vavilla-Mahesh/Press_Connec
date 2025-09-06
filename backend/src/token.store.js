const { getPool } = require('./database');

const storeTokens = async (username, tokens, encryptionKey) => {
  const pool = getPool();
  const client = await pool.connect();
  
  try {
    const expiresAt = new Date(tokens.expires_in || Date.now() + 3600000); // Default 1 hour if not provided
    
    await client.query(`
      INSERT INTO youtube_tokens (username, access_token, refresh_token, token_type, expires_at, scope)
      VALUES ($1, pgp_sym_encrypt($2, $6), pgp_sym_encrypt($3, $6), $4, $5, pgp_sym_encrypt($7, $6))
      ON CONFLICT (username) 
      DO UPDATE SET 
        access_token = pgp_sym_encrypt($2, $6),
        refresh_token = pgp_sym_encrypt($3, $6),
        token_type = $4,
        expires_at = $5,
        scope = pgp_sym_encrypt($7, $6),
        updated_at = CURRENT_TIMESTAMP
    `, [
      username,
      tokens.access_token,
      tokens.refresh_token || '',
      tokens.token_type || 'Bearer',
      expiresAt,
      encryptionKey,
      tokens.scope || ''
    ]);
    
    console.log(`Tokens stored for user: ${username}`);
  } catch (error) {
    console.error('Error storing tokens:', error);
    throw error;
  } finally {
    client.release();
  }
};

const getTokens = async (username, encryptionKey) => {
  const pool = getPool();
  const client = await pool.connect();
  
  try {
    // First check if user has their own tokens
    let result = await client.query(`
      SELECT 
        pgp_sym_decrypt(access_token, $2) as access_token,
        pgp_sym_decrypt(refresh_token, $2) as refresh_token,
        token_type,
        expires_at,
        pgp_sym_decrypt(scope, $2) as scope
      FROM youtube_tokens 
      WHERE username = $1
    `, [username, encryptionKey]);
    
    if (result.rows.length > 0) {
      const tokens = result.rows[0];
      return {
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        token_type: tokens.token_type,
        expires_in: tokens.expires_at,
        scope: tokens.scope
      };
    }
    
    // If no tokens found, check if user is associated with someone and get their tokens
    const userResult = await client.query(
      'SELECT associated_with FROM users WHERE username = $1',
      [username]
    );
    
    if (userResult.rows.length > 0 && userResult.rows[0].associated_with) {
      const associatedWith = userResult.rows[0].associated_with;
      
      result = await client.query(`
        SELECT 
          pgp_sym_decrypt(access_token, $2) as access_token,
          pgp_sym_decrypt(refresh_token, $2) as refresh_token,
          token_type,
          expires_at,
          pgp_sym_decrypt(scope, $2) as scope
        FROM youtube_tokens 
        WHERE username = $1
      `, [associatedWith, encryptionKey]);
      
      if (result.rows.length > 0) {
        const tokens = result.rows[0];
        console.log(`Retrieved tokens for ${username} from associated user: ${associatedWith}`);
        return {
          access_token: tokens.access_token,
          refresh_token: tokens.refresh_token,
          token_type: tokens.token_type,
          expires_in: tokens.expires_at,
          scope: tokens.scope
        };
      }
    }
    
    return null;
  } catch (error) {
    console.error('Error retrieving tokens:', error);
    throw error;
  } finally {
    client.release();
  }
};

const deleteTokens = async (username) => {
  const pool = getPool();
  const client = await pool.connect();
  
  try {
    await client.query('DELETE FROM youtube_tokens WHERE username = $1', [username]);
    console.log(`Tokens deleted for user: ${username}`);
  } catch (error) {
    console.error('Error deleting tokens:', error);
    throw error;
  } finally {
    client.release();
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

const refreshExpiredTokens = async (encryptionKey, oauthConfig, googleOAuth) => {
  const pool = getPool();
  const client = await pool.connect();
  
  try {
    // Find tokens expiring in the next 5 minutes
    const result = await client.query(`
      SELECT username, 
             pgp_sym_decrypt(refresh_token, $1) as refresh_token,
             expires_at
      FROM youtube_tokens 
      WHERE expires_at <= CURRENT_TIMESTAMP + INTERVAL '5 minutes'
      AND pgp_sym_decrypt(refresh_token, $1) != ''
    `, [encryptionKey]);
    
    for (const row of result.rows) {
      try {
        console.log(`Refreshing tokens for user: ${row.username}`);
        
        const refreshedTokens = await googleOAuth.refreshAccessToken(
          row.refresh_token,
          oauthConfig
        );
        
        if (refreshedTokens) {
          // Update tokens in database
          await storeTokens(row.username, refreshedTokens, encryptionKey);
          console.log(`Tokens refreshed successfully for user: ${row.username}`);
        }
      } catch (error) {
        console.error(`Failed to refresh tokens for user ${row.username}:`, error);
      }
    }
  } catch (error) {
    console.error('Error in token refresh system:', error);
  } finally {
    client.release();
  }
};

module.exports = {
  storeTokens,
  getTokens,
  deleteTokens,
  isTokenExpired,
  refreshExpiredTokens
};