const googleOAuth = require('./google.oauth');
const tokenStore = require('./token.store');
const { retryApiCall, circuitBreakers } = require('./error-recovery');

/**
 * Get live stream analytics data from YouTube Analytics API
 */
const getStreamAnalytics = async (req, res) => {
  try {
    const { streamId, broadcastId, startDate, endDate } = req.query;
    const username = req.user.username;
    
    if (!streamId && !broadcastId) {
      return res.status(400).json({ error: 'Stream ID or Broadcast ID required' });
    }

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
      
      tokens = { ...tokens, ...refreshedTokens };
      await tokenStore.storeTokens(username, tokens);
    }

    // Get YouTube Analytics API instance
    const youtube = googleOAuth.getYouTubeAPI(tokens.access_token);
    const youtubeAnalytics = googleOAuth.getYouTubeAnalyticsAPI(tokens.access_token);

    // Default date range (last 7 days if not specified)
    const defaultEndDate = new Date().toISOString().split('T')[0];
    const defaultStartDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];

    const analyticsStartDate = startDate || defaultStartDate;
    const analyticsEndDate = endDate || defaultEndDate;

    // Get basic stream info
    let streamInfo = null;
    if (broadcastId) {
      try {
        const broadcastResponse = await youtube.liveBroadcasts.list({
          part: ['snippet', 'status', 'statistics'],
          id: broadcastId
        });
        streamInfo = broadcastResponse.data.items[0];
      } catch (error) {
        console.warn('Could not fetch broadcast info:', error.message);
      }
    }

    // Get analytics data
    const analyticsPromises = [];

    // Viewer count over time
    analyticsPromises.push(
      youtubeAnalytics.reports.query({
        ids: 'channel==MINE',
        startDate: analyticsStartDate,
        endDate: analyticsEndDate,
        metrics: 'views,estimatedMinutesWatched,averageViewDuration',
        dimensions: 'day',
        sort: 'day'
      }).catch(error => {
        console.warn('Analytics query failed:', error.message);
        return { data: { rows: [] } };
      })
    );

    // Real-time metrics if stream is live
    if (streamInfo && streamInfo.status.lifeCycleStatus === 'live') {
      analyticsPromises.push(
        youtube.videos.list({
          part: ['liveStreamingDetails', 'statistics'],
          id: streamInfo.snippet.title // Assuming video ID is available
        }).catch(error => {
          console.warn('Live metrics query failed:', error.message);
          return { data: { items: [] } };
        })
      );
    }

    const [analyticsData, liveMetrics] = await Promise.all(analyticsPromises);

    // Format response
    const analytics = {
      streamInfo: streamInfo ? {
        id: streamInfo.id,
        title: streamInfo.snippet.title,
        status: streamInfo.status.lifeCycleStatus,
        scheduledStartTime: streamInfo.snippet.scheduledStartTime,
        actualStartTime: streamInfo.snippet.actualStartTime,
        actualEndTime: streamInfo.snippet.actualEndTime,
        concurrentViewers: streamInfo.statistics?.concurrentViewers || 0
      } : null,
      metrics: {
        dateRange: {
          startDate: analyticsStartDate,
          endDate: analyticsEndDate
        },
        totalViews: 0,
        totalWatchTime: 0,
        averageViewDuration: 0,
        dailyData: analyticsData.data.rows || []
      },
      liveMetrics: liveMetrics?.data.items[0]?.liveStreamingDetails || null
    };

    // Calculate totals from daily data
    if (analyticsData.data.rows && analyticsData.data.rows.length > 0) {
      analytics.metrics.totalViews = analyticsData.data.rows.reduce((sum, row) => sum + (row[1] || 0), 0);
      analytics.metrics.totalWatchTime = analyticsData.data.rows.reduce((sum, row) => sum + (row[2] || 0), 0);
      
      const totalDuration = analyticsData.data.rows.reduce((sum, row) => sum + (row[3] || 0), 0);
      analytics.metrics.averageViewDuration = totalDuration / analyticsData.data.rows.length;
    }

    res.json({
      success: true,
      analytics
    });

  } catch (error) {
    console.error('Get stream analytics error:', error);
    
    if (error.code === 401) {
      res.status(401).json({ error: 'YouTube authentication invalid' });
    } else if (error.code === 403) {
      res.status(403).json({ error: 'YouTube Analytics API access denied' });
    } else {
      res.status(500).json({ 
        error: 'Failed to get stream analytics',
        details: error.message
      });
    }
  }
};

/**
 * Get real-time stream metrics for live streams
 */
const getLiveMetrics = async (req, res) => {
  try {
    const { broadcastId } = req.query;
    const username = req.user.username;
    
    if (!broadcastId) {
      return res.status(400).json({ error: 'Broadcast ID required' });
    }

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
      
      tokens = { ...tokens, ...refreshedTokens };
      await tokenStore.storeTokens(username, tokens);
    }

    // Get YouTube API instance
    const youtube = googleOAuth.getYouTubeAPI(tokens.access_token);

    // Get live broadcast details
    const broadcastResponse = await youtube.liveBroadcasts.list({
      part: ['snippet', 'status', 'statistics'],
      id: broadcastId
    });

    if (!broadcastResponse.data.items || broadcastResponse.data.items.length === 0) {
      return res.status(404).json({ error: 'Broadcast not found' });
    }

    const broadcast = broadcastResponse.data.items[0];
    
    // Real-time metrics
    const metrics = {
      broadcastId: broadcast.id,
      status: broadcast.status.lifeCycleStatus,
      concurrentViewers: broadcast.statistics?.concurrentViewers || 0,
      totalChatMessages: broadcast.statistics?.totalChatMessages || 0,
      timestamp: new Date().toISOString()
    };

    res.json({
      success: true,
      metrics
    });

  } catch (error) {
    console.error('Get live metrics error:', error);
    
    if (error.code === 401) {
      res.status(401).json({ error: 'YouTube authentication invalid' });
    } else if (error.code === 403) {
      res.status(403).json({ error: 'YouTube API access denied' });
    } else {
      res.status(500).json({ 
        error: 'Failed to get live metrics',
        details: error.message
      });
    }
  }
};

module.exports = {
  getStreamAnalytics,
  getLiveMetrics
};