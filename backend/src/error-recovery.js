/**
 * Retry utility with exponential backoff and circuit breaker pattern
 */

class CircuitBreaker {
  constructor(threshold = 5, timeout = 60000) {
    this.threshold = threshold;
    this.timeout = timeout;
    this.failureCount = 0;
    this.lastFailureTime = null;
    this.state = 'CLOSED'; // CLOSED, OPEN, HALF_OPEN
  }

  async execute(operation) {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailureTime > this.timeout) {
        this.state = 'HALF_OPEN';
      } else {
        throw new Error('Circuit breaker is OPEN');
      }
    }

    try {
      const result = await operation();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  onSuccess() {
    this.failureCount = 0;
    this.state = 'CLOSED';
  }

  onFailure() {
    this.failureCount++;
    this.lastFailureTime = Date.now();
    
    if (this.failureCount >= this.threshold) {
      this.state = 'OPEN';
    }
  }

  getState() {
    return this.state;
  }
}

/**
 * Retry function with exponential backoff
 */
async function retry(operation, options = {}) {
  const {
    maxAttempts = 3,
    baseDelay = 1000,
    maxDelay = 30000,
    backoffFactor = 2,
    jitter = true
  } = options;

  let lastError;
  
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      
      if (attempt === maxAttempts) {
        break;
      }

      // Don't retry on authentication errors
      if (error.code === 401 || error.code === 403) {
        break;
      }

      // Calculate delay with exponential backoff
      let delay = Math.min(baseDelay * Math.pow(backoffFactor, attempt - 1), maxDelay);
      
      // Add jitter to prevent thundering herd
      if (jitter) {
        delay += Math.random() * 1000;
      }

      console.log(`Attempt ${attempt} failed, retrying in ${delay}ms:`, error.message);
      await sleep(delay);
    }
  }
  
  throw lastError;
}

/**
 * Retry specifically for API calls with different error handling
 */
async function retryApiCall(apiCall, options = {}) {
  const {
    maxAttempts = 3,
    baseDelay = 1000,
    shouldRetry = (error) => {
      // Retry on network errors and server errors (5xx)
      if (error.code >= 500) return true;
      if (error.code === 'ECONNRESET' || error.code === 'ENOTFOUND') return true;
      if (error.message && error.message.includes('timeout')) return true;
      return false;
    }
  } = options;

  return retry(apiCall, {
    ...options,
    maxAttempts,
    baseDelay,
    shouldRetry: (error) => {
      if (!shouldRetry(error)) {
        throw error; // Don't retry, throw immediately
      }
      return true;
    }
  });
}

/**
 * Sleep utility
 */
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Fallback handler for streaming operations
 */
class StreamingFallback {
  constructor() {
    this.fallbackStrategies = [];
  }

  addFallback(strategy) {
    this.fallbackStrategies.push(strategy);
  }

  async execute(primaryOperation, context = {}) {
    try {
      return await primaryOperation();
    } catch (primaryError) {
      console.log('Primary streaming operation failed:', primaryError.message);
      
      for (let i = 0; i < this.fallbackStrategies.length; i++) {
        try {
          console.log(`Attempting fallback strategy ${i + 1}`);
          return await this.fallbackStrategies[i](context, primaryError);
        } catch (fallbackError) {
          console.log(`Fallback strategy ${i + 1} failed:`, fallbackError.message);
          
          if (i === this.fallbackStrategies.length - 1) {
            // All fallbacks failed
            throw new Error(`All streaming strategies failed. Primary: ${primaryError.message}, Last fallback: ${fallbackError.message}`);
          }
        }
      }
    }
  }
}

// Global circuit breakers for different services
const circuitBreakers = {
  youtube: new CircuitBreaker(3, 30000),
  analytics: new CircuitBreaker(5, 60000),
  streaming: new CircuitBreaker(2, 45000)
};

module.exports = {
  CircuitBreaker,
  retry,
  retryApiCall,
  StreamingFallback,
  circuitBreakers,
  sleep
};