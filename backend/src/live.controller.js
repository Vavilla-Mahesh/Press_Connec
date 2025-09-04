const googleOAuth = require('./google.oauth');
const tokenStore = require('./token.store');

const createLiveStream = async (req, res) => {
  try {
    const username = req.user.username;

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

    // Get YouTube API instance
    const youtube = googleOAuth.getYouTubeAPI(tokens.access_token);

    // Create live broadcast with recording enabled (or omit recording params)
    const broadcastResponse = await youtube.liveBroadcasts.insert({
      part: ['snippet', 'status', 'contentDetails'],
      requestBody: {
        snippet: {
          title: `Press Connect Live - ${new Date().toISOString()}`,
          description: 'Live stream from Press Connect app',
          scheduledStartTime: new Date().toISOString(),
        },
        status: {
          privacyStatus: 'public',
          selfDeclaredMadeForKids: false
        },
        contentDetails: {
          enableAutoStart: true,
          enableAutoStop: true,
          enableDvr: true,
          enableContentEncryption: false,
          startWithSlate: false,
          // Remove recordFromStart or set to true
          recordFromStart: true, // Changed from false to true
          enableClosedCaptions: false,
          closedCaptionsType: 'closedCaptionsDisabled',
          projection: 'rectangular',
          enableLowLatency: true
        }
      }
    });

    const broadcast = broadcastResponse.data;

    // Create live stream with optimized settings for auto-live
    const streamResponse = await youtube.liveStreams.insert({
      part: ['snippet', 'cdn'],
      requestBody: {
        snippet: {
          title: `Press Connect Stream - ${new Date().toISOString()}`
        },
        cdn: {
          frameRate: '30fps',
          ingestionType: 'rtmp',
          resolution: '1080p',
          format: '1080p_hfr'
        }
      }
    });

    const stream = streamResponse.data;

    // Bind broadcast to stream
    await youtube.liveBroadcasts.bind({
      part: ['id'],
      id: broadcast.id,
      streamId: stream.id
    });

    console.log(`Broadcast ${broadcast.id} created and bound to stream ${stream.id}`);
    console.log(`Auto-live enabled: ${broadcast.contentDetails?.enableAutoStart}`);

    // Return stream information with auto-live status
    res.json({
      success: true,
      broadcastId: broadcast.id,
      streamId: stream.id,
      ingestUrl: stream.cdn.ingestionInfo.ingestionAddress,
      streamKey: stream.cdn.ingestionInfo.streamName,
      autoLiveEnabled: true,
      enableAutoStart: broadcast.contentDetails?.enableAutoStart || false,
      status: broadcast.status.lifeCycleStatus
    });

  } catch (error) {
    console.error('Create live stream error:', error);

    if (error.code === 401) {
      res.status(401).json({ error: 'YouTube authentication invalid' });
    } else if (error.code === 403) {
      // More specific error handling for recording permission
      if (error.message && error.message.includes('disable recording')) {
        res.status(403).json({
          error: 'YouTube account does not have permission to disable recording. Please enable live streaming in YouTube Studio or use a verified account.'
        });
      } else {
        res.status(403).json({ error: 'YouTube live streaming not enabled for this account' });
      }
    } else {
      res.status(500).json({
        error: 'Failed to create live stream',
        details: error.message
      });
    }
  }
};

// Alternative version with minimal content details (fallback approach)
const createLiveStreamMinimal = async (req, res) => {
  try {
    const username = req.user.username;
    let tokens = await tokenStore.getTokens(username);

    if (!tokens) {
      return res.status(401).json({ error: 'YouTube not connected' });
    }

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

      tokens = { ...tokens, ...refreshedTokens };
      await tokenStore.storeTokens(username, tokens);
    }

    const youtube = googleOAuth.getYouTubeAPI(tokens.access_token);

    // Minimal broadcast creation - let YouTube use defaults
    const broadcastResponse = await youtube.liveBroadcasts.insert({
      part: ['snippet', 'status'],
      requestBody: {
        snippet: {
          title: `Press Connect Live - ${new Date().toISOString()}`,
          description: 'Live stream from Press Connect app',
          scheduledStartTime: new Date().toISOString(),
        },
        status: {
          privacyStatus: 'public',
          selfDeclaredMadeForKids: false
        }
        // Omit contentDetails to use YouTube defaults
      }
    });

    const broadcast = broadcastResponse.data;

    const streamResponse = await youtube.liveStreams.insert({
      part: ['snippet', 'cdn'],
      requestBody: {
        snippet: {
          title: `Press Connect Stream - ${new Date().toISOString()}`
        },
        cdn: {
          frameRate: '30fps',
          ingestionType: 'rtmp',
          resolution: '1080p'
        }
      }
    });

    const stream = streamResponse.data;

    await youtube.liveBroadcasts.bind({
      part: ['id'],
      id: broadcast.id,
      streamId: stream.id
    });

    console.log(`Minimal broadcast ${broadcast.id} created and bound to stream ${stream.id}`);

    res.json({
      success: true,
      broadcastId: broadcast.id,
      streamId: stream.id,
      ingestUrl: stream.cdn.ingestionInfo.ingestionAddress,
      streamKey: stream.cdn.ingestionInfo.streamName,
      autoLiveEnabled: false, // Will need manual transition
      status: broadcast.status.lifeCycleStatus
    });

  } catch (error) {
    console.error('Create minimal live stream error:', error);
    res.status(500).json({
      error: 'Failed to create live stream',
      details: error.message
    });
  }
};

// New endpoint to check and force live status
const checkAndGoLive = async (req, res) => {
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

    // Check current broadcast status
    const broadcastResponse = await youtube.liveBroadcasts.list({
      part: ['status', 'snippet'],
      id: [broadcastId]
    });

    if (!broadcastResponse.data.items || broadcastResponse.data.items.length === 0) {
      return res.status(404).json({ error: 'Broadcast not found' });
    }

    const broadcast = broadcastResponse.data.items[0];
    const currentStatus = broadcast.status.lifeCycleStatus;

    console.log(`Broadcast ${broadcastId} current status: ${currentStatus}`);

    // If already live, return success
    if (currentStatus === 'live') {
      return res.json({
        success: true,
        status: 'live',
        message: 'Broadcast is already live'
      });
    }

    // If ready or testing, try to transition to live
    if (currentStatus === 'ready' || currentStatus === 'testing') {
      try {
        await youtube.liveBroadcasts.transition({
          part: ['status'],
          id: broadcastId,
          broadcastStatus: 'live'
        });

        console.log(`Successfully transitioned broadcast ${broadcastId} to live`);

        return res.json({
          success: true,
          status: 'live',
          message: 'Broadcast transitioned to live successfully'
        });
      } catch (transitionError) {
        console.error('Transition to live failed:', transitionError.message);

        return res.json({
          success: false,
          status: currentStatus,
          message: `Transition failed: ${transitionError.message}`,
          canRetry: true
        });
      }
    }

    // For other statuses, return current status
    res.json({
      success: false,
      status: currentStatus,
      message: `Broadcast is in ${currentStatus} status. Waiting for RTMP stream to start.`,
      canRetry: currentStatus !== 'complete'
    });

  } catch (error) {
    console.error('Check and go live error:', error);
    res.status(500).json({
      error: 'Failed to check broadcast status',
      details: error.message
    });
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

    // Check current status first
    const broadcastResponse = await youtube.liveBroadcasts.list({
      part: ['status'],
      id: [broadcastId]
    });

    if (broadcastResponse.data.items && broadcastResponse.data.items.length > 0) {
      const currentStatus = broadcastResponse.data.items[0].status.lifeCycleStatus;

      console.log(`Ending broadcast ${broadcastId} with current status: ${currentStatus}`);

      // Only transition if not already complete
      if (currentStatus !== 'complete') {
        await youtube.liveBroadcasts.transition({
          part: ['status'],
          id: broadcastId,
          broadcastStatus: 'complete'
        });
      }
    }

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
  createLiveStreamMinimal, // Add this as a fallback option
  checkAndGoLive,
  endLiveStream,
  transitionBroadcast
};