import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
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
  bool _isRecording = false;
  List<CameraDescription> _cameras = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
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

  void _initializeServices() {
    // Wire up watermark service with live service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final liveService = Provider.of<LiveService>(context, listen: false);
      final watermarkService = Provider.of<WatermarkService>(context, listen: false);
      
      liveService.setWatermarkService(watermarkService);
    });
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
        
        // Set camera controller in LiveService for RTMP streaming
        if (mounted) {
          final liveService = Provider.of<LiveService>(context, listen: false);
          liveService.setCameraController(_cameraController);
          
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
                          
                          const SizedBox(width: 12),
                          
                          // Video Recording Button
                          Container(
                            decoration: BoxDecoration(
                              gradient: _isRecording 
                                ? LinearGradient(colors: [Colors.red, Colors.red.shade700])
                                : ThemeService.accentGradient,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: IconButton(
                              onPressed: _toggleVideoRecording,
                              icon: Icon(
                                _isRecording ? Icons.stop : Icons.videocam,
                                color: Colors.white,
                              ),
                              tooltip: _isRecording ? 'Stop Recording' : 'Start Recording',
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

  void _takeSnapshot() async {
    try {
      // Request permissions
      final hasPermission = await _requestGalleryPermission();
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gallery permission denied')),
        );
        return;
      }

      // Use live service to take snapshot with watermark
      final liveService = Provider.of<LiveService>(context, listen: false);
      final snapshotPath = await liveService.takeSnapshot();
      
      if (snapshotPath != null) {
        // Save to gallery
        final result = await ImageGallerySaver.saveFile(snapshotPath);
        
        if (result['isSuccess'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Snapshot with watermark saved to gallery!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save snapshot')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to take snapshot')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error taking snapshot: $e')),
      );
    }
  }

  void _toggleVideoRecording() async {
    try {
      final liveService = Provider.of<LiveService>(context, listen: false);
      
      if (_isRecording) {
        // Stop recording using live service
        final videoPath = await liveService.stopRecording();
        
        if (videoPath != null) {
          // Request permissions and save to gallery
          final hasPermission = await _requestGalleryPermission();
          if (hasPermission) {
            final result = await ImageGallerySaver.saveFile(videoPath);
            
            if (result['isSuccess'] == true) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Video with watermark saved to gallery!')),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to save video')),
              );
            }
          }
        }

        setState(() {
          _isRecording = false;
        });
      } else {
        // Start recording using live service
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final outputPath = '${tempDir.path}/recording_$timestamp.mp4';
        
        final success = await liveService.startRecording(outputPath);
        
        if (success) {
          setState(() {
            _isRecording = true;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording with watermark started')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to start recording')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error with video recording: $e')),
      );
    }
  }

  Future<bool> _requestGalleryPermission() async {
    // For Android 13+ (API 33+), we need different permissions
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+ uses scoped storage
        final photos = await Permission.photos.request();
        final videos = await Permission.videos.request();
        return photos.isGranted && videos.isGranted;
      } else {
        // Android 12 and below
        final storage = await Permission.storage.request();
        return storage.isGranted;
      }
    } else if (Platform.isIOS) {
      final photos = await Permission.photos.request();
      return photos.isGranted;
    }
    return true;
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