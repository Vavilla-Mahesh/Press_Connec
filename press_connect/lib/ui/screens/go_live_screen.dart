import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../../config.dart';
import '../../services/live_service.dart';
import '../../services/theme_service.dart';
import '../../services/rtmp_streaming_service.dart';
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
    final liveService = Provider.of<LiveService>(context, listen: false);
    await liveService.streamingService.initialize();
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
          child: Column(
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
                        Consumer<LiveService>(
                          builder: (context, liveService, child) {
                            final streamingService = liveService.streamingService;
                            
                            if (streamingService.isCameraInitialized && streamingService.cameraController != null) {
                              return SizedBox.expand(
                                child: CameraPreview(streamingService.cameraController!),
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
                        
                        // Live Indicator
                        Consumer<LiveService>(
                          builder: (context, liveService, child) {
                            if (!liveService.isLive) {
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
                      // Stream Status Card
                      Consumer<LiveService>(
                        builder: (context, liveService, child) {
                          return GlassCard(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      liveService.isLive ? Icons.broadcast_on_home : Icons.videocam,
                                      color: liveService.isLive ? Colors.red : Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      liveService.isLive ? 'Live Streaming' : 'Ready to Stream',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (liveService.isLive)
                                      const Text(
                                        '● LIVE',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  liveService.isLive 
                                    ? 'Broadcasting to YouTube'
                                    : 'Camera ready for streaming',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 14,
                                  ),
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
                            child: Consumer<LiveService>(
                              builder: (context, liveService, child) {
                                return AnimatedButton(
                                  onPressed: liveService.canStartStream
                                      ? _handleGoLive
                                      : liveService.canStopStream
                                          ? _handleStopStream
                                          : null,
                                  gradient: liveService.isLive
                                      ? LinearGradient(
                                          colors: [Colors.red, Colors.red.shade700],
                                        )
                                      : ThemeService.primaryGradient,
                                  child: liveService.streamState == StreamState.preparing
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : Text(
                                          liveService.isLive ? 'Stop Live' : 'Go Live',
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
                          
                          // Camera Switch Button
                          Consumer<LiveService>(
                            builder: (context, liveService, child) {
                              return Container(
                                decoration: BoxDecoration(
                                  gradient: ThemeService.accentGradient,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: IconButton(
                                  onPressed: !liveService.isLive ? _switchCamera : null,
                                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                                  tooltip: 'Switch Camera',
                                ),
                              );
                            },
                          ),
                          
                          const SizedBox(width: 8),
                          
                          // Snapshot Button
                          Container(
                            decoration: BoxDecoration(
                              gradient: ThemeService.accentGradient,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: IconButton(
                              onPressed: _takeSnapshot,
                              icon: const Icon(Icons.camera_alt, color: Colors.white),
                              tooltip: 'Take Snapshot',
                            ),
                          ),
                        ],
                      ),
                      
                      // Error Display
                      Consumer<LiveService>(
                        builder: (context, liveService, child) {
                          if (liveService.errorMessage != null) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                liveService.errorMessage!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => const SettingsBottomSheet(),
    );
  }

  void _handleGoLive() async {
    final liveService = Provider.of<LiveService>(context, listen: false);
    
    // First create the stream
    final streamCreated = await liveService.createLiveStream();
    if (!streamCreated) return;
    
    // Then start streaming
    final success = await liveService.startStream();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start live stream')),
      );
    }
  }

  void _handleStopStream() async {
    final liveService = Provider.of<LiveService>(context, listen: false);
    await liveService.stopStream();
  }

  void _switchCamera() async {
    final liveService = Provider.of<LiveService>(context, listen: false);
    final success = await liveService.streamingService.switchCamera();
    
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to switch camera')),
      );
    }
  }

  void _takeSnapshot() {
    // Implementation for taking snapshots
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Snapshot taken!')),
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
            'Stream Settings',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          
          // Stream Quality Info
          Consumer<LiveService>(
            builder: (context, liveService, child) {
              return ListTile(
                leading: const Icon(Icons.high_quality),
                title: const Text('Stream Quality'),
                subtitle: Text(
                  '${AppConfig.defaultResolution['width']}x${AppConfig.defaultResolution['height']} @ ${AppConfig.defaultBitrate} kbps',
                ),
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