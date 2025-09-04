const fs = require('fs').promises;
const path = require('path');

const TOKENS_FILE = path.join(__dirname, '..', 'tokens.json');

// Initialize tokens file if it doesn't exist
const initializeTokensFile = async () => {
  try {
    await fs.access(TOKENS_FILE);
  } catch (error) {
    // File doesn't exist, create it
    await fs.writeFile(TOKENS_FILE, JSON.stringify({}));
  }
};

const loadTokens = async () => {
  try {
    await initializeTokensFile();
    const data = await fs.readFile(TOKENS_FILE, 'utf8');
    return JSON.parse(data);
  } catch (error) {
    console.error('Error loading tokens:', error);
    return {};
  }
};

const saveTokens = async (tokens) => {
  try {
    await fs.writeFile(TOKENS_FILE, JSON.stringify(tokens, null, 2));
  } catch (error) {
    console.error('Error saving tokens:', error);
  }
};

const storeTokens = async (username, tokens) => {
  const allTokens = await loadTokens();
  allTokens[username] = {
    ...tokens,
    updated_at: new Date().toISOString()
  };
  await saveTokens(allTokens);
};

const getTokens = async (username) => {
  const allTokens = await loadTokens();
  return allTokens[username] || null;
};

const deleteTokens = async (username) => {
  const allTokens = await loadTokens();
  delete allTokens[username];
  await saveTokens(allTokens);
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