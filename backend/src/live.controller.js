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

    // Bind broadcast to stream
    await youtube.liveBroadcasts.bind({
      part: ['id'],
      id: broadcast.id,
      streamId: stream.id
    });

    // Return stream information
    res.json({
      success: true,
      broadcastId: broadcast.id,
      streamId: stream.id,
      ingestUrl: stream.cdn.ingestionInfo.ingestionAddress,
      streamKey: stream.cdn.ingestionInfo.streamName
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

    // First check the current broadcast status
    const broadcastDetails = await youtube.liveBroadcasts.list({
      part: ['status'],
      id: broadcastId
    });

    if (!broadcastDetails.data.items || broadcastDetails.data.items.length === 0) {
      return res.status(404).json({ error: 'Broadcast not found' });
    }

    const broadcast = broadcastDetails.data.items[0];
    const currentStatus = broadcast.status.lifeCycleStatus;

    // Check if already complete
    if (currentStatus === 'complete') {
      return res.json({
        success: true,
        message: 'Live stream is already ended'
      });
    }

    // Only transition if the broadcast is in a valid state to be completed
    if (currentStatus === 'ready' || currentStatus === 'testing') {
      return res.status(400).json({
        error: 'Cannot end stream',
        message: 'Broadcast must be live before it can be ended',
        details: `Current status: ${currentStatus}`
      });
    }

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
    
    // Provide more specific error messages
    if (error.errors && error.errors.some(err => err.reason === 'invalidTransition')) {
      res.status(400).json({
        error: 'Invalid transition',
        message: 'This broadcast cannot be ended in its current state. It may not be live yet.',
        details: error.message
      });
    } else {
      res.status(500).json({ 
        error: 'Failed to end live stream',
        details: error.message
      });
    }
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

    // For live transitions, check stream status and retry if needed
    if (broadcastStatus === 'live') {
      const maxRetries = 3;
      const retryDelays = [5000, 20000, 60000]; // 5s, 20s, 60s
      
      for (let attempt = 0; attempt < maxRetries; attempt++) {
        try {
          // Get broadcast status first
          const broadcastDetails = await youtube.liveBroadcasts.list({
            part: ['status', 'snippet'],
            id: broadcastId
          });

          if (!broadcastDetails.data.items || broadcastDetails.data.items.length === 0) {
            return res.status(404).json({ error: 'Broadcast not found' });
          }

          const broadcast = broadcastDetails.data.items[0];
          
          // Check if already live
          if (broadcast.status.lifeCycleStatus === 'live') {
            return res.json({
              success: true,
              message: 'Broadcast is already live'
            });
          }

          // Attempt transition
          await youtube.liveBroadcasts.transition({
            part: ['status'],
            id: broadcastId,
            broadcastStatus: broadcastStatus
          });

          // If successful, return immediately
          return res.json({
            success: true,
            message: `Broadcast transitioned to ${broadcastStatus} successfully`
          });

        } catch (transitionError) {
          // Check if this is a stream inactive error
          if (transitionError.errors && 
              transitionError.errors.some(err => err.reason === 'errorStreamInactive')) {
            
            if (attempt < maxRetries - 1) {
              const delay = retryDelays[attempt];
              console.log(`Stream is inactive, retrying transition in ${delay/1000} seconds (attempt ${attempt + 1})...`);
              
              // Send intermediate response for long delays
              if (attempt === 0) {
                // Don't send response yet, just log
              }
              
              await new Promise(resolve => setTimeout(resolve, delay));
              continue; // Retry
            } else {
              // Final attempt failed
              return res.status(400).json({
                error: 'Stream is inactive',
                message: 'Please ensure you are streaming video to the RTMP endpoint before going live. The stream needs to be actively broadcasting video data.',
                details: 'No video data detected at the RTMP ingest URL. Start your streaming software and try again.'
              });
            }
          } else {
            // Other error, don't retry
            throw transitionError;
          }
        }
      }
    } else {
      // For non-live transitions (like complete), attempt directly
      await youtube.liveBroadcasts.transition({
        part: ['status'],
        id: broadcastId,
        broadcastStatus: broadcastStatus
      });

      res.json({
        success: true,
        message: `Broadcast transitioned to ${broadcastStatus} successfully`
      });
    }

  } catch (error) {
    console.error('Transition broadcast error:', error);
    
    // Provide more specific error messages
    if (error.errors && error.errors.some(err => err.reason === 'invalidTransition')) {
      res.status(400).json({
        error: 'Invalid transition',
        message: 'This broadcast cannot be transitioned to the requested status. Check the current broadcast state.',
        details: error.message
      });
    } else if (error.errors && error.errors.some(err => err.reason === 'errorStreamInactive')) {
      res.status(400).json({
        error: 'Stream is inactive',
        message: 'Please ensure you are streaming video to the RTMP endpoint before going live.',
        details: error.message
      });
    } else {
      res.status(500).json({ 
        error: 'Failed to transition broadcast',
        details: error.message
      });
    }
  }
};

const checkStreamStatus = async (req, res) => {
  try {
    const { broadcastId } = req.query;
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

    // Get broadcast details
    const broadcastDetails = await youtube.liveBroadcasts.list({
      part: ['status', 'snippet'],
      id: broadcastId
    });

    if (!broadcastDetails.data.items || broadcastDetails.data.items.length === 0) {
      return res.status(404).json({ error: 'Broadcast not found' });
    }

    const broadcast = broadcastDetails.data.items[0];
    
    // Get associated stream details if available
    let streamDetails = null;
    if (broadcast.contentDetails && broadcast.contentDetails.boundStreamId) {
      try {
        const streamResponse = await youtube.liveStreams.list({
          part: ['status', 'snippet'],
          id: broadcast.contentDetails.boundStreamId
        });
        
        if (streamResponse.data.items && streamResponse.data.items.length > 0) {
          streamDetails = streamResponse.data.items[0];
        }
      } catch (streamError) {
        console.warn('Could not fetch stream details:', streamError.message);
      }
    }

    res.json({
      success: true,
      broadcast: {
        id: broadcast.id,
        title: broadcast.snippet.title,
        lifeCycleStatus: broadcast.status.lifeCycleStatus,
        privacyStatus: broadcast.status.privacyStatus,
        recordingStatus: broadcast.status.recordingStatus
      },
      stream: streamDetails ? {
        id: streamDetails.id,
        title: streamDetails.snippet.title,
        status: streamDetails.status.streamStatus,
        healthStatus: streamDetails.status.healthStatus
      } : null,
      canTransitionToLive: broadcast.status.lifeCycleStatus === 'ready' && 
                          streamDetails && 
                          streamDetails.status.streamStatus === 'active',
      message: getStatusMessage(broadcast.status.lifeCycleStatus, streamDetails)
    });

  } catch (error) {
    console.error('Check stream status error:', error);
    res.status(500).json({ 
      error: 'Failed to check stream status',
      details: error.message
    });
  }
};

// Helper function to provide user-friendly status messages
const getStatusMessage = (lifeCycleStatus, streamDetails) => {
  if (lifeCycleStatus === 'live') {
    return 'Broadcast is currently live';
  } else if (lifeCycleStatus === 'complete') {
    return 'Broadcast has ended';
  } else if (lifeCycleStatus === 'ready') {
    if (!streamDetails) {
      return 'Broadcast is ready, but stream details unavailable';
    } else if (streamDetails.status.streamStatus === 'active') {
      return 'Stream is active and ready to go live';
    } else if (streamDetails.status.streamStatus === 'inactive') {
      return 'Stream is inactive. Please start streaming video to the RTMP endpoint';
    } else {
      return `Stream status: ${streamDetails.status.streamStatus}`;
    }
  } else {
    return `Broadcast status: ${lifeCycleStatus}`;
  }
};

module.exports = {
  createLiveStream,
  endLiveStream,
  transitionBroadcast,
  checkStreamStatus
};