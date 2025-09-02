import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../../services/live_service.dart';
import '../../services/watermark_service.dart';
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
  CameraController? _cameraController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isCameraInitialized = false;
  List<CameraDescription> _cameras = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeAnimations();
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

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _cameraController = CameraController(
          _cameras.first,
          ResolutionPreset.high,
          enableAudio: true,
        );
        
        await _cameraController!.initialize();
        
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera initialization failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
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
                        if (_isCameraInitialized && _cameraController != null)
                          SizedBox.expand(
                            child: CameraPreview(_cameraController!),
                          )
                        else
                          Container(
                            color: Colors.black,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
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
                            child: Consumer<LiveService>(
                              builder: (context, liveService, child) {
                                return AnimatedButton(
                                  onPressed: liveService.canStartStream
                                      ? _handleGoLive
                                      : liveService.canStopStream
                                          ? _handleStopStream
                                          : null,
                                  gradient: (liveService.isLive || liveService.isTesting)
                                      ? LinearGradient(
                                          colors: [Colors.red, Colors.red.shade700],
                                        )
                                      : ThemeService.primaryGradient,
                                  child: liveService.streamState == StreamState.preparing ||
                                         liveService.streamState == StreamState.stopping
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : Text(
                                          _getButtonText(liveService.streamState),
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
                          
                          // Action Buttons (Snapshot, Record)
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
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not ready')),
      );
      return;
    }

    final liveService = Provider.of<LiveService>(context, listen: false);
    final watermarkService = Provider.of<WatermarkService>(context, listen: false);
    
    // First create the stream
    final streamCreated = await liveService.createLiveStream();
    if (!streamCreated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create stream: ${liveService.errorMessage}')),
        );
      }
      return;
    }
    
    // Then start streaming with camera and watermark
    final success = await liveService.startStream(
      cameraController: _cameraController!,
      watermarkService: watermarkService,
    );
    
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start live stream: ${liveService.errorMessage}')),
      );
    }
  }

  void _handleStopStream() async {
    final liveService = Provider.of<LiveService>(context, listen: false);
    await liveService.stopStream(cameraController: _cameraController);
  }

  void _takeSnapshot() {
    // Implementation for taking snapshots
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Snapshot taken!')),
    );
  }

  String _getButtonText(StreamState state) {
    switch (state) {
      case StreamState.idle:
        return 'Go Live';
      case StreamState.preparing:
      case StreamState.stopping:
        return 'Loading...';
      case StreamState.testing:
        return 'Stop Test';
      case StreamState.live:
        return 'Stop Live';
      case StreamState.error:
        return 'Retry';
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
          
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}