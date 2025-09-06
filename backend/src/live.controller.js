const googleOAuth = require('./google.oauth');
const tokenStore = require('./token.store');

const createLiveStream = async (req, res) => {
  try {
    const username = req.user.username;
    
    // Get stored tokens for this user (supports association)
    let tokens = await tokenStore.getTokens(username, req.config.encryption.key);
    
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
      
      // Update stored tokens - store under the original token owner
      const tokenOwner = req.user.associatedWith || username;
      tokens = { ...tokens, ...refreshedTokens };
      await tokenStore.storeTokens(tokenOwner, tokens, req.config.encryption.key);
    }

    // Get YouTube API instance
    const youtube = googleOAuth.getYouTubeAPI(tokens.access_token);

    // Create live broadcast
    const broadcastResponse = await youtube.liveBroadcasts.insert({
      part: ['snippet', 'status'],
      requestBody: {
        snippet: {
          title: `Press Connect Live - ${new Date().toISOString()}`,
          description: 'Live stream from Press Connect app',
          scheduledStartTime: new Date().toISOString(),
          scheduledEndTime: new Date(Date.now() + 4 * 60 * 60 * 1000).toISOString() // 4 hours
        },
        status: {
          privacyStatus: 'public',
          selfDeclaredMadeForKids: false
        }
      }
    });

    const broadcast = broadcastResponse.data;

    // Create live stream
    const streamResponse = await youtube.liveStreams.insert({
      part: ['snippet', 'cdn'],
      requestBody: {
        snippet: {
          title: `Press Connect Stream - ${new Date().toISOString()}`
        },
        cdn: {
          frameRate: '30fps',
          ingestionType: 'rtmp',
          resolution: '720p'
        }
      }
    });

    const stream = streamResponse.data;

    // Bind stream to broadcast
    await youtube.liveBroadcasts.bind({
      part: ['snippet'],
      id: broadcast.id,
      streamId: stream.id
    });

    res.json({
      success: true,
      broadcast: {
        id: broadcast.id,
        title: broadcast.snippet.title,
        status: broadcast.status.lifeCycleStatus,
        streamUrl: `rtmp://a.rtmp.youtube.com/live2/${stream.cdn.ingestionInfo.streamName}`,
        streamKey: stream.cdn.ingestionInfo.streamName,
        watchUrl: `https://www.youtube.com/watch?v=${broadcast.id}`
      }
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
    const tokens = await tokenStore.getTokens(username, req.config.encryption.key);
    
    if (!tokens) {
      return res.status(401).json({ error: 'YouTube not connected' });
    }

    // Get YouTube API instance
    const youtube = googleOAuth.getYouTubeAPI(tokens.access_token);

    // Transition broadcast to complete
    await youtube.liveBroadcasts.transition({
      part: ['status'],
      id: broadcastId,
      broadcastStatus: 'complete'
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

module.exports = {
  createLiveStream,
  endLiveStream
};