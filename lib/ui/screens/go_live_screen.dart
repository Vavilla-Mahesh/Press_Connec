import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:apivideo_live_stream/apivideo_live_stream.dart';
import '../../services/live_service.dart';
import '../../services/watermark_service.dart';
import '../../services/theme_service.dart';
import '../../services/apivideo_live_stream_service.dart';
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

  @override
  void initState() {
    super.initState();
    // Force landscape orientation for this screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initializeAnimations();
    _initializeStreaming();
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

  Future<void> _initializeStreaming() async {
    final streamService = Provider.of<ApiVideoLiveStreamService>(context, listen: false);
    final success = await streamService.initialize();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize streaming: ${streamService.errorMessage}')),
      );
    }
  }

  @override
  void dispose() {
    // Restore orientation to all when leaving the screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
          child: _buildLandscapeLayout(),
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout() {
    return Row(
      children: [
        // Camera Preview Section
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
                  // Camera Preview
                  Consumer<ApiVideoLiveStreamService>(
                    builder: (context, streamService, child) {
                      if (streamService.controller != null && 
                          streamService.state != StreamingState.idle) {
                        return SizedBox.expand(
                          child: ApiVideoCameraPreview(
                            controller: streamService.controller!,
                          ),
                        );
                      } else {
                        return Container(
                          color: Colors.black,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                    },
                  ),
                  
                  // Watermark Overlay
                  Consumer<WatermarkService>(
                    builder: (context, watermarkService, child) {
                      if (!watermarkService.isEnabled) {
                        return const SizedBox.shrink();
                      }
                      
                      return Positioned.fill(
                        child: AnimatedOpacity(
                          opacity: watermarkService.alphaValue,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            decoration: const BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage('assets/watermarks/default_watermark.png'),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  
                  // Live Indicator
                  Consumer<ApiVideoLiveStreamService>(
                    builder: (context, streamService, child) {
                      if (!streamService.isStreaming) {
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
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.3),
                                      blurRadius: 8,
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
                  ),

                  // Camera Controls Overlay
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Column(
                      children: [
                        // Switch Camera Button
                        Consumer<ApiVideoLiveStreamService>(
                          builder: (context, streamService, child) {
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: streamService.isStreaming ? null : () async {
                                  final success = await streamService.switchCamera();
                                  if (!success && mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Failed to switch camera')),
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.cameraswitch,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        
                        // Mute/Unmute Button
                        Consumer<ApiVideoLiveStreamService>(
                          builder: (context, streamService, child) {
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: () async {
                                  final success = await streamService.toggleMute();
                                  if (!success && mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Failed to toggle mute')),
                                    );
                                  }
                                },
                                icon: Icon(
                                  streamService.isMuted ? Icons.mic_off : Icons.mic,
                                  color: streamService.isMuted ? Colors.red : Colors.white,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Controls Section
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Watermark Opacity Slider
                Consumer<WatermarkService>(
                  builder: (context, watermarkService, child) {
                    return GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.opacity),
                              const SizedBox(width: 8),
                              const Text(
                                'Watermark Opacity',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Text('${watermarkService.opacityPercentage}%'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Slider(
                            value: watermarkService.opacity,
                            min: 0.0,
                            max: 1.0,
                            divisions: 100,
                            onChanged: watermarkService.setOpacity,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                
                const SizedBox(height: 24),
                
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: Consumer<ApiVideoLiveStreamService>(
                        builder: (context, streamService, child) {
                          return AnimatedButton(
                            onPressed: streamService.canStartStream
                                ? _handleGoLive
                                : streamService.canStopStream
                                    ? _handleStopStream
                                    : null,
                            gradient: streamService.isStreaming
                                ? LinearGradient(
                                    colors: [Colors.red, Colors.red.shade700],
                                  )
                                : ThemeService.primaryGradient,
                            child: streamService.state == StreamingState.initializing ||
                                    streamService.state == StreamingState.stopping
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Text(
                                    streamService.isStreaming ? 'Stop Live' : 'Go Live',
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
                    const SizedBox(width: 16),
                    Expanded(
                      child: AnimatedButton(
                        onPressed: _takeSnapshot,
                        gradient: LinearGradient(
                          colors: [Colors.grey, Colors.grey.shade700],
                        ),
                        child: const Text(
                          'Snapshot',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Stream Status
                Consumer<ApiVideoLiveStreamService>(
                  builder: (context, streamService, child) {
                    if (streamService.errorMessage != null) {
                      return GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.error, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                streamService.errorMessage!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                            TextButton(
                              onPressed: streamService.clearError,
                              child: const Text('Dismiss'),
                            ),
                          ],
                        ),
                      );
                    }
                    
                    return GlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            _getStatusIcon(streamService.state),
                            color: _getStatusColor(streamService.state),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _getStatusText(streamService.state),
                            style: TextStyle(
                              color: _getStatusColor(streamService.state),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _getStatusIcon(StreamingState state) {
    switch (state) {
      case StreamingState.idle:
        return Icons.radio_button_unchecked;
      case StreamingState.initializing:
        return Icons.refresh;
      case StreamingState.ready:
        return Icons.check_circle;
      case StreamingState.streaming:
        return Icons.live_tv;
      case StreamingState.stopping:
        return Icons.stop;
      case StreamingState.error:
        return Icons.error;
    }
  }

  Color _getStatusColor(StreamingState state) {
    switch (state) {
      case StreamingState.idle:
        return Colors.grey;
      case StreamingState.initializing:
        return Colors.blue;
      case StreamingState.ready:
        return Colors.green;
      case StreamingState.streaming:
        return Colors.red;
      case StreamingState.stopping:
        return Colors.orange;
      case StreamingState.error:
        return Colors.red;
    }
  }

  String _getStatusText(StreamingState state) {
    switch (state) {
      case StreamingState.idle:
        return 'Not initialized';
      case StreamingState.initializing:
        return 'Initializing...';
      case StreamingState.ready:
        return 'Ready to stream';
      case StreamingState.streaming:
        return 'Live streaming';
      case StreamingState.stopping:
        return 'Stopping...';
      case StreamingState.error:
        return 'Error occurred';
    }
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => const SettingsBottomSheet(),
    );
  }

  void _handleGoLive() async {
    final liveService = Provider.of<LiveService>(context, listen: false);
    final streamService = Provider.of<ApiVideoLiveStreamService>(context, listen: false);
    
    // First create the stream in backend
    final streamCreated = await liveService.createLiveStream();
    if (!streamCreated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create stream: ${liveService.errorMessage}')),
        );
      }
      return;
    }
    
    // Get the RTMP URL for ApiVideo (convert from YouTube RTMP)
    final streamInfo = liveService.currentStream;
    if (streamInfo == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No stream information available')),
        );
      }
      return;
    }
    
    // Start streaming using the stream key
    final success = await streamService.startStreaming(streamInfo.streamKey);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start live stream: ${streamService.errorMessage}')),
      );
    }
  }

  void _handleStopStream() async {
    final liveService = Provider.of<LiveService>(context, listen: false);
    final streamService = Provider.of<ApiVideoLiveStreamService>(context, listen: false);
    
    // Stop the ApiVideo stream
    await streamService.stopStreaming();
    
    // Stop the backend stream
    await liveService.stopStream();
  }

  void _takeSnapshot() {
    // Implementation for taking snapshots
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Snapshot feature not implemented yet')),
    );
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
            'Settings',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          
          Consumer<WatermarkService>(
            builder: (context, watermarkService, child) {
              return SwitchListTile(
                title: const Text('Enable Watermark'),
                subtitle: const Text('Show watermark overlay on stream'),
                value: watermarkService.isEnabled,
                onChanged: (value) => watermarkService.setEnabled(value),
              );
            },
          ),
          
          const SizedBox(height: 16),
          
          Consumer<ApiVideoLiveStreamService>(
            builder: (context, streamService, child) {
              return ListTile(
                leading: Icon(
                  streamService.isMuted ? Icons.mic_off : Icons.mic,
                  color: streamService.isMuted ? Colors.red : null,
                ),
                title: Text(streamService.isMuted ? 'Microphone Muted' : 'Microphone Active'),
                subtitle: const Text('Tap to toggle microphone'),
                onTap: () async {
                  await streamService.toggleMute();
                },
              );
            },
          ),
          
          const SizedBox(height: 16),
          
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}