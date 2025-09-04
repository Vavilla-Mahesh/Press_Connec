import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:apivideo_live_stream/apivideo_live_stream.dart';
import '../../services/streaming_service.dart';
import '../../services/youtube_api_service.dart';
import '../../services/camera_service.dart';
import '../../services/connection_service.dart';
import '../../services/theme_service.dart';
import '../widgets/animated_gradient_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_button.dart';

class GoLiveScreen extends StatefulWidget {
  const GoLiveScreen({super.key});

  @override
  State<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends State<GoLiveScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // Stream duration timer
  DateTime? _streamStartTime;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeServices();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _pulseController.repeat(reverse: true);
  }

  Future<void> _initializeServices() async {
    final cameraService = Provider.of<CameraService>(context, listen: false);
    final connectionService = Provider.of<ConnectionService>(context, listen: false);

    // Initialize camera service (just for permissions and orientation)
    await cameraService.initialize(
      preferredCamera: CameraType.back,
    );

    // Initialize connection monitoring
    await connectionService.initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Go Live'),
        actions: [
          IconButton(
            onPressed: _showSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: OrientationBuilder(
            builder: (context, orientation) {
              // Force landscape layout regardless of device orientation
              return _buildLandscapeLayout();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout() {
    return Row(
      children: [
        // Camera Preview Section (Left side - larger)
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  _buildCameraPreview(),
                  _buildLiveIndicator(),
                  _buildCameraInfo(),
                  _buildConnectionIndicator(),
                ],
              ),
            ),
          ),
        ),

        // Controls Section (Right side)
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildConnectionStatusCard(),
                  const SizedBox(height: 16),
                  _buildStreamStatusCard(),
                  const SizedBox(height: 16),
                  _buildControlButtons(),
                  const SizedBox(height: 16),
                  _buildStreamMetrics(),
                  _buildErrorDisplay(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraPreview() {
    return Consumer<StreamingService>(
      builder: (context, streamingService, child) {
        if (streamingService.isInitialized && streamingService.controller != null) {
          return SizedBox.expand(
            child: AspectRatio(
              aspectRatio: 16 / 9, // Force 16:9 landscape aspect ratio
              child: ApiVideoCameraPreview(
                controller: streamingService.controller!,
                enableZoomOnPinch: true,
              ),
            ),
          );
        } else {
          return Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    streamingService.state == StreamingState.error 
                        ? 'Streaming Error' 
                        : 'Initializing camera...',
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (streamingService.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        streamingService.errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildLiveIndicator() {
    return Consumer<StreamingService>(
      builder: (context, streamingService, child) {
        if (streamingService.state != StreamingState.streaming) {
          return const SizedBox.shrink();
        }

        return Positioned(
          top: 16,
          left: 16,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCameraInfo() {
    return Consumer<StreamingService>(
      builder: (context, streamingService, child) {
        if (!streamingService.isInitialized) return const SizedBox.shrink();

        return Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'CAMERA', // The apivideo package handles camera switching internally
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionIndicator() {
    return Consumer<ConnectionService>(
      builder: (context, connectionService, child) {
        Color indicatorColor;
        IconData indicatorIcon;
        
        switch (connectionService.status) {
          case ConnectionStatus.connected:
            indicatorColor = connectionService.isGoodForStreaming ? Colors.green : Colors.orange;
            indicatorIcon = Icons.wifi;
            break;
          case ConnectionStatus.weak:
            indicatorColor = Colors.orange;
            indicatorIcon = Icons.wifi_1_bar;
            break;
          case ConnectionStatus.unstable:
            indicatorColor = Colors.red;
            indicatorIcon = Icons.wifi_off;
            break;
          default:
            indicatorColor = Colors.grey;
            indicatorIcon = Icons.wifi_off;
        }

        return Positioned(
          bottom: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  indicatorIcon,
                  color: indicatorColor,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  connectionService.connectionQuality,
                  style: TextStyle(
                    color: indicatorColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionStatusCard() {
    return Consumer<ConnectionService>(
      builder: (context, connectionService, child) {
        return GlassCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    connectionService.isConnected ? Icons.wifi : Icons.wifi_off,
                    color: connectionService.isGoodForStreaming ? Colors.green : Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Connection: ${connectionService.connectionQuality}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (connectionService.currentMetrics != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Upload: ${connectionService.currentMetrics!.uploadSpeed.toStringAsFixed(1)} Mbps',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 10,
                  ),
                ),
                Text(
                  'Ping: ${connectionService.currentMetrics!.ping}ms',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStreamStatusCard() {
    return Consumer2<StreamingService, YouTubeApiService>(
      builder: (context, streamingService, youtubeService, child) {
        return GlassCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    streamingService.isStreaming ? Icons.broadcast_on_home : Icons.videocam,
                    color: streamingService.isStreaming ? Colors.red : Colors.grey,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getStreamStatusText(streamingService, youtubeService),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (streamingService.isStreaming)
                    const Text(
                      '● LIVE',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _getStreamSubtitle(streamingService, youtubeService),
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 10,
                ),
              ),
              if (streamingService.isStreaming && streamingService.streamDuration != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Duration: ${_formatDuration(streamingService.streamDuration!)}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main Go Live Button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: Consumer3<StreamingService, YouTubeApiService, ConnectionService>(
            builder: (context, streamingService, youtubeService, connectionService, child) {
              final isReady = streamingService.canStartStream && 
                              connectionService.isGoodForStreaming;
              final isStreaming = streamingService.isStreaming;
              final isLoading = streamingService.state == StreamingState.connecting ||
                               youtubeService.status == YouTubeStreamStatus.creating;

              return AnimatedButton(
                onPressed: isLoading ? null : (isStreaming ? _handleStopStream : (isReady ? _handleGoLive : null)),
                gradient: isStreaming
                    ? LinearGradient(
                        colors: [Colors.red, Colors.red.shade700],
                      )
                    : ThemeService.primaryGradient,
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        isStreaming ? 'Stop Live' : 'Go Live',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        // Secondary Buttons Row
        Row(
          children: [
            // Camera Switch Button
            Expanded(
              child: Consumer<StreamingService>(
                builder: (context, streamingService, child) {
                  final canSwitch = streamingService.isInitialized && 
                                   !streamingService.isStreaming;

                  return Container(
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: canSwitch
                          ? ThemeService.accentGradient
                          : LinearGradient(
                              colors: [Colors.grey.shade600, Colors.grey.shade700],
                            ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: canSwitch ? _switchCamera : null,
                        child: const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.flip_camera_ios, color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Switch',
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(width: 8),

            // Quality Button
            Expanded(
              child: Consumer<StreamingService>(
                builder: (context, streamingService, child) {
                  return Container(
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: ThemeService.accentGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _showQualitySelector,
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.high_quality, color: Colors.white, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                _getQualityText(streamingService.quality),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStreamMetrics() {
    return Consumer<StreamingService>(
      builder: (context, streamingService, child) {
        if (!streamingService.isStreaming) {
          return const SizedBox.shrink();
        }

        return GlassCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Stream Metrics',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Bitrate:',
                    style: TextStyle(color: Colors.grey[400], fontSize: 10),
                  ),
                  Text(
                    '${(streamingService.currentBitrate / 1000000).toStringAsFixed(1)} Mbps',
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Quality:',
                    style: TextStyle(color: Colors.grey[400], fontSize: 10),
                  ),
                  Text(
                    _getQualityText(streamingService.quality),
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
              if (streamingService.frameDropCount > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Dropped frames:',
                      style: TextStyle(color: Colors.orange[400], fontSize: 10),
                    ),
                    Text(
                      streamingService.frameDropCount.toString(),
                      style: TextStyle(color: Colors.orange[400], fontSize: 10),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorDisplay() {
    return Consumer3<StreamingService, YouTubeApiService, ConnectionService>(
      builder: (context, streamingService, youtubeService, connectionService, child) {
        String? errorMessage;
        
        if (streamingService.errorMessage != null) {
          errorMessage = streamingService.errorMessage;
        } else if (youtubeService.errorMessage != null) {
          errorMessage = youtubeService.errorMessage;
        } else if (connectionService.errorMessage != null) {
          errorMessage = connectionService.errorMessage;
        }

        if (errorMessage == null) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorMessage,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: _clearErrors,
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getStreamStatusText(StreamingService streamingService, YouTubeApiService youtubeService) {
    if (streamingService.isStreaming) {
      return 'Live Streaming';
    } else if (streamingService.state == StreamingState.connecting) {
      return 'Connecting...';
    } else if (youtubeService.status == YouTubeStreamStatus.creating) {
      return 'Setting up...';
    } else if (streamingService.state == StreamingState.ready) {
      return 'Ready to Stream';
    } else {
      return 'Initializing...';
    }
  }

  String _getStreamSubtitle(StreamingService streamingService, YouTubeApiService youtubeService) {
    if (streamingService.isStreaming) {
      return 'Broadcasting to YouTube Live';
    } else if (youtubeService.hasActiveStream) {
      return 'YouTube stream ready';
    } else {
      return 'Camera ready for streaming';
    }
  }

  String _getQualityText(StreamQuality quality) {
    switch (quality) {
      case StreamQuality.low:
        return '480p';
      case StreamQuality.medium:
        return '720p';
      case StreamQuality.high:
        return '1080p';
      case StreamQuality.auto:
        return 'Auto';
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => const SettingsBottomSheet(),
    );
  }

  void _showQualitySelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => const QualitySelector(),
    );
  }

  Future<void> _handleGoLive() async {
    final streamingService = Provider.of<StreamingService>(context, listen: false);
    final youtubeService = Provider.of<YouTubeApiService>(context, listen: false);
    final connectionService = Provider.of<ConnectionService>(context, listen: false);

    // Check connection quality
    if (!connectionService.isGoodForStreaming) {
      _showConnectionWarning();
      return;
    }

    try {
      // First create YouTube stream
      final streamInfo = await youtubeService.createYouTubeLiveStream();
      if (streamInfo == null) {
        _showError('Failed to create YouTube stream');
        return;
      }

      // Initialize streaming service with the stream key
      final initialized = await streamingService.initializeStreaming(streamInfo.streamKey);
      if (!initialized) {
        _showError('Failed to initialize streaming');
        return;
      }

      // Start YouTube broadcast
      final broadcastStarted = await youtubeService.startYouTubeBroadcast();
      if (!broadcastStarted) {
        _showError('Failed to start YouTube broadcast');
        return;
      }

      // Start streaming
      final streamStarted = await streamingService.startYouTubeStream();
      if (!streamStarted) {
        _showError('Failed to start stream');
        return;
      }

      _streamStartTime = DateTime.now();
      
    } catch (e) {
      _showError('Error starting stream: $e');
    }
  }

  Future<void> _handleStopStream() async {
    final streamingService = Provider.of<StreamingService>(context, listen: false);
    final youtubeService = Provider.of<YouTubeApiService>(context, listen: false);

    try {
      // Stop streaming first
      await streamingService.stopStream();
      
      // End YouTube broadcast
      await youtubeService.endYouTubeBroadcast();
      
      _streamStartTime = null;
      
    } catch (e) {
      _showError('Error stopping stream: $e');
    }
  }

  Future<void> _switchCamera() async {
    final streamingService = Provider.of<StreamingService>(context, listen: false);
    final success = await streamingService.switchCamera();

    if (!success && mounted) {
      _showError('Failed to switch camera');
    }
  }

  void _showConnectionWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection Quality Warning'),
        content: Consumer<ConnectionService>(
          builder: (context, connectionService, child) {
            final recommendations = connectionService.getStreamingRecommendations();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your connection may not be optimal for streaming:'),
                const SizedBox(height: 8),
                ...recommendations.map((recommendation) => 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $recommendation', style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _handleGoLive();
            },
            child: const Text('Stream Anyway'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  void _clearErrors() {
    final streamingService = Provider.of<StreamingService>(context, listen: false);
    final youtubeService = Provider.of<YouTubeApiService>(context, listen: false);
    final connectionService = Provider.of<ConnectionService>(context, listen: false);

    streamingService.clearError();
    youtubeService.clearError();
    connectionService.clearError();
  }
}

class SettingsBottomSheet extends StatelessWidget {
  const SettingsBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Stream Settings',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Consumer3<StreamingService, CameraService, ConnectionService>(
            builder: (context, streamingService, cameraService, connectionService, child) {
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.high_quality),
                    title: const Text('Stream Quality'),
                    subtitle: Text(_getQualityDescription(streamingService.quality)),
                    onTap: () {
                      Navigator.pop(context);
                      _showQualitySelector(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.camera),
                    title: const Text('Camera'),
                    subtitle: Text('${cameraService.currentCameraType.name.toUpperCase()} - ${cameraService.resolution.name}'),
                  ),
                  ListTile(
                    leading: Icon(
                      connectionService.isConnected ? Icons.wifi : Icons.wifi_off,
                      color: connectionService.isGoodForStreaming ? Colors.green : Colors.orange,
                    ),
                    title: const Text('Connection'),
                    subtitle: Text('${connectionService.connectionQuality} - ${connectionService.currentMetrics?.uploadSpeed.toStringAsFixed(1) ?? '0'} Mbps'),
                  ),
                  if (streamingService.isStreaming) ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.timer, color: Colors.red),
                      title: const Text('Live Duration'),
                      subtitle: Text(streamingService.streamDuration != null 
                          ? _formatDuration(streamingService.streamDuration!) 
                          : '00:00:00'),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _getQualityDescription(StreamQuality quality) {
    switch (quality) {
      case StreamQuality.low:
        return '480p - 1 Mbps (Mobile data friendly)';
      case StreamQuality.medium:
        return '720p - 2.5 Mbps (Recommended)';
      case StreamQuality.high:
        return '1080p - 4 Mbps (High quality)';
      case StreamQuality.auto:
        return 'Auto - Adapts to connection';
    }
  }

  void _showQualitySelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => const QualitySelector(),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }
}

class QualitySelector extends StatelessWidget {
  const QualitySelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Stream Quality',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Consumer<StreamingService>(
            builder: (context, streamingService, child) {
              return Column(
                children: StreamQuality.values.map((quality) {
                  return ListTile(
                    leading: Radio<StreamQuality>(
                      value: quality,
                      groupValue: streamingService.quality,
                      onChanged: streamingService.isStreaming ? null : (value) {
                        if (value != null) {
                          streamingService.updateStreamQuality(value);
                          Navigator.pop(context);
                        }
                      },
                    ),
                    title: Text(_getQualityText(quality)),
                    subtitle: Text(_getQualityDescription(quality)),
                    enabled: !streamingService.isStreaming,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _getQualityText(StreamQuality quality) {
    switch (quality) {
      case StreamQuality.low:
        return '480p Low';
      case StreamQuality.medium:
        return '720p Medium';
      case StreamQuality.high:
        return '1080p High';
      case StreamQuality.auto:
        return 'Auto Quality';
    }
  }

  String _getQualityDescription(StreamQuality quality) {
    switch (quality) {
      case StreamQuality.low:
        return '1 Mbps - Best for mobile data';
      case StreamQuality.medium:
        return '2.5 Mbps - Recommended for most users';
      case StreamQuality.high:
        return '4 Mbps - High quality, requires good connection';
      case StreamQuality.auto:
        return 'Automatically adjusts based on connection';
    }
  }
}