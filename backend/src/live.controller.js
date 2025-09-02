

const googleOAuth = require('./google.oauth');
const tokenStore = require('./token.store');
const { retryApiCall, circuitBreakers, StreamingFallback } = require('./error-recovery');

const createLiveStream = async (req, res) => {
  try {
    const username = req.user.username;
    const {
      title,
      description,
      quality = '720p',
      visibility = 'public',
      status = 'live'
    } = req.body;

    // Get stored tokens for this user
    let tokens = await tokenStore.getTokens(username);

    if (!tokens) {
      return res.status(401).json({ error: 'YouTube not connected' });
    }

    // Check if token needs refresh
    if (tokenStore.isTokenExpired(tokens)) {
      if (!tokens.refresh_token) {
        return res.status(401).json({ error: 'YouTube authentication expired, please reconnect' });
      }

      const refreshedTokens = await googleOAuth.refreshAccessToken(
        tokens.refresh_token,
        req.config.oauth
      );

      if (!refreshedTokens) {
        return res.status(401).json({ error: 'Failed to refresh YouTube authentication' });
      }

      // Update stored tokens
      tokens = { ...tokens, ...refreshedTokens };
      await tokenStore.storeTokens(username, tokens);
    }

    // Validate input parameters
    const validQualities = ['720p', '1080p'];
    const validVisibilities = ['public', 'unlisted', 'private'];
    const validStatuses = ['live', 'scheduled', 'offline'];

    if (!validQualities.includes(quality)) {
      return res.status(400).json({ error: 'Invalid quality. Use 720p or 1080p' });
    }

    if (!validVisibilities.includes(visibility)) {
      return res.status(400).json({ error: 'Invalid visibility. Use public, unlisted, or private' });
    }

    if (!validStatuses.includes(status)) {
      return res.status(400).json({ error: 'Invalid status. Use live, scheduled, or offline' });
    }

    // Get YouTube API instance
    const youtube = googleOAuth.getYouTubeAPI(tokens.access_token);

    // Configure stream settings based on quality
    const streamSettings = {
      '720p': { resolution: '720p', frameRate: '30fps' },
      '1080p': { resolution: '1080p', frameRate: '30fps' }
    };

    const currentSettings = streamSettings[quality];

    // Create live broadcast with retry and circuit breaker
    const broadcastResponse = await circuitBreakers.youtube.execute(async () => {
      return await retryApiCall(async () => {
        return await youtube.liveBroadcasts.insert({
          part: ['snippet', 'status'],
          requestBody: {
            snippet: {
              title: title || `Press Connect Live - ${new Date().toISOString()}`,
              description: description || 'Live stream from Press Connect app',
              scheduledStartTime: new Date().toISOString(),
              scheduledEndTime: new Date(Date.now() + 4 * 60 * 60 * 1000).toISOString() // 4 hours
            },
            status: {
              privacyStatus: visibility,
              selfDeclaredMadeForKids: false
            }
          }
        });
      }, { maxAttempts: 3, baseDelay: 1000 });
    });

    const broadcast = broadcastResponse.data;

    // Create live stream with retry
    const streamResponse = await circuitBreakers.youtube.execute(async () => {
      return await retryApiCall(async () => {
        return await youtube.liveStreams.insert({
          part: ['snippet', 'cdn'],
          requestBody: {
            snippet: {
              title: `Press Connect Stream - ${new Date().toISOString()}`
            },
            cdn: {
              frameRate: currentSettings.frameRate,
              ingestionType: 'rtmp',
              resolution: currentSettings.resolution
            }
          }
        });
      }, { maxAttempts: 3, baseDelay: 1000 });
    });

    const stream = streamResponse.data;

    // Bind broadcast to stream with retry
    await circuitBreakers.youtube.execute(async () => {
      return await retryApiCall(async () => {
        return await youtube.liveBroadcasts.bind({
          part: ['id'],
          id: broadcast.id,
          streamId: stream.id
        });
      }, { maxAttempts: 3, baseDelay: 500 });
    });

    // Return stream information
    res.json({
      success: true,
      broadcastId: broadcast.id,
      streamId: stream.id,
      ingestUrl: stream.cdn.ingestionInfo.ingestionAddress,
      streamKey: stream.cdn.ingestionInfo.streamName,
      quality: quality,
      visibility: visibility,
      status: status,
      title: broadcast.snippet.title,
      watchUrl: `https://youtu.be/${broadcast.id}`
    });

  } catch (error) {
    console.error('Create live stream error:', error);

    if (error.code === 401) {
      res.status(401).json({ error: 'YouTube authentication invalid' });
    } else if (error.code === 403) {
      res.status(403).json({ error: 'YouTube live streaming not enabled for this account' });
    } else {
      res.status(500).json({
        error: 'Failed to create live stream',
        details: error.message
      });
    }
  }
};

const endLiveStream = async (req, res) => {
  try {
    const { broadcastId } = req.body;
    const username = req.user.username;

    if (!broadcastId) {
      return res.status(400).json({ error: 'Broadcast ID required' });
    }

    // Get stored tokens for this user
    const tokens = await tokenStore.getTokens(username);

    if (!tokens) {
      return res.status(401).json({ error: 'YouTube not connected' });
    }

    // Get YouTube API instance
    const youtube = googleOAuth.getYouTubeAPI(tokens.access_token);

    // Transition broadcast to complete with retry
    await circuitBreakers.youtube.execute(async () => {
      return await retryApiCall(async () => {
        return await youtube.liveBroadcasts.transition({
          part: ['status'],
          id: broadcastId,
          broadcastStatus: 'complete'
        });
      }, { maxAttempts: 3, baseDelay: 1000 });
    });

    res.json({
      success: true,
      message: 'Live stream ended successfully'
    });

  } catch (error) {
    console.error('End live stream error:', error);
    res.status(500).json({
      error: 'Failed to end live stream',
      details: error.message
    });
  }
};

const transitionBroadcast = async (req, res) => {
  try {
    const { broadcastId, broadcastStatus } = req.body;
    const username = req.user.username;

    if (!broadcastId || !broadcastStatus) {
      return res.status(400).json({ error: 'Broadcast ID and status required' });
    }

    // Validate broadcast status
    const validStatuses = ['live', 'complete'];
    if (!validStatuses.includes(broadcastStatus)) {
      return res.status(400).json({ error: 'Invalid broadcast status' });
    }

    // Get stored tokens for this user
    const tokens = await tokenStore.getTokens(username);

    if (!tokens) {
      return res.status(401).json({ error: 'YouTube not connected' });
    }

    // Get YouTube API instance
    const youtube = googleOAuth.getYouTubeAPI(tokens.access_token);

    // Transition broadcast status
    await youtube.liveBroadcasts.transition({
      part: ['status'],
      id: broadcastId,
      broadcastStatus: broadcastStatus
    });

    res.json({
      success: true,
      message: `Broadcast transitioned to ${broadcastStatus} successfully`
    });

  } catch (error) {
    console.error('Transition broadcast error:', error);
    res.status(500).json({
      error: 'Failed to transition broadcast',
      details: error.message
    });
  }
};

module.exports = {
  createLiveStream,
  endLiveStream,
  transitionBroadcast
};