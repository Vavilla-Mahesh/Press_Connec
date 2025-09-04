import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rtmp_broadcaster/camera.dart';
import '../../config.dart';
import '../../services/live_service.dart';
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
    final liveService = Provider.of<LiveService>(context, listen: false);
    await liveService.streamingService.initialize();
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
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;

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
          child: isLandscape
              ? _buildLandscapeLayout()
              : _buildPortraitLayout(),
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout() {
    return Row(
      children: [
        // Camera Preview Section (Left side)
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Color.fromARGB((0.3 * 255).toInt(), 0, 0, 0),
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

                      if (streamingService.isCameraInitialized &&
                          streamingService.cameraController != null &&
                          streamingService.cameraController!.value.isInitialized) {
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
                  _buildLiveIndicator(),
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
                  _buildStreamStatusCard(),
                  const SizedBox(height: 16),
                  _buildControlButtons(),
                  _buildErrorDisplay(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout() {
    return Column(
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
                  color: Color.fromARGB((0.3 * 255).toInt(), 0, 0, 0),
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

                      if (streamingService.isCameraInitialized &&
                          streamingService.cameraController != null &&
                          streamingService.cameraController!.value.isInitialized) {
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
                  _buildLiveIndicator(),
                ],
              ),
            ),
          ),
        ),

        // Controls Section
        Flexible(
          flex: 2,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStreamStatusCard(),
                  const SizedBox(height: 16),
                  _buildControlButtons(),
                  _buildErrorDisplay(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveIndicator() {
    return Consumer<LiveService>(
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
                        color: Color.fromARGB((0.5 * 255).toInt(), 255, 0, 0),
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

  Widget _buildStreamStatusCard() {
    return Consumer<LiveService>(
      builder: (context, liveService, child) {
        return GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    liveService.isLive ? Icons.broadcast_on_home : Icons.videocam,
                    color: liveService.isLive ? Colors.red : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      liveService.isLive ? 'Live Streaming' : 'Ready to Stream',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (liveService.isLive)
                    const Text(
                      '● LIVE',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                liveService.isLive
                    ? 'Broadcasting to YouTube'
                    : 'Camera ready for streaming',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
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

        const SizedBox(height: 12),

        // Secondary Buttons Row
        Row(
          children: [
            // Camera Switch Button
            Expanded(
              child: Consumer<LiveService>(
                builder: (context, liveService, child) {
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
                        onTap: !liveService.isLive ? _switchCamera : null,
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

            // Snapshot Button
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  gradient: ThemeService.accentGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _takeSnapshot,
                    child: const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Photo',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorDisplay() {
    return Consumer<LiveService>(
      builder: (context, liveService, child) {
        if (liveService.errorMessage != null) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              liveService.errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }
        return const SizedBox.shrink();
      },
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

    // Show dialog to choose streaming method
    final streamingChoice = await _showStreamingChoiceDialog();
    if (streamingChoice == null) return;

    if (streamingChoice == 'youtube') {
      // YouTube streaming (existing functionality)
      final streamCreated = await liveService.createLiveStream();
      if (!streamCreated) return;

      final success = await liveService.startStream();
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start live stream')),
        );
      }
    } else if (streamingChoice == 'rtmp') {
      // Custom RTMP URL streaming
      final rtmpUrl = await _showRtmpUrlDialog();
      if (rtmpUrl != null && rtmpUrl.isNotEmpty) {
        final success = await liveService.streamingService.startStreaming(rtmpUrl);
        if (success) {
          liveService.setState(StreamState.live);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to start RTMP streaming')),
          );
        }
      }
    }
  }

  Future<String?> _showStreamingChoiceDialog() async {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Choose Streaming Method'),
          content: const Text('How would you like to stream?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('youtube'),
              child: const Text('YouTube Live'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('rtmp'),
              child: const Text('Custom RTMP'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showRtmpUrlDialog() async {
    final textController = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter RTMP URL'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(
              hintText: 'rtmp://example.com/live/streamkey',
              labelText: 'RTMP URL',
            ),
            keyboardType: TextInputType.url,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(textController.text),
              child: const Text('Start Streaming'),
            ),
          ],
        );
      },
    );
  }

  void _handleStopStream() async {
    final liveService = Provider.of<LiveService>(context, listen: false);
    
    // Stop RTMP streaming if active
    if (liveService.streamingService.isStreaming) {
      await liveService.streamingService.stopStreaming();
    }
    
    // Stop YouTube streaming if active
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

  void _takeSnapshot() async {
    final liveService = Provider.of<LiveService>(context, listen: false);
    try {
      await liveService.streamingService.takeSnapshot();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Snapshot saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to take snapshot')),
        );
      }
    }
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