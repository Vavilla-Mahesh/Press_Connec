import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
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
            onPressed: _showStreamSettings,
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
                        
                        // Stream Status Indicator
                        Consumer<LiveService>(
                          builder: (context, liveService, child) {
                            if (liveService.streamState == StreamState.idle) {
                              return const SizedBox.shrink();
                            }
                            
                            String statusText;
                            Color statusColor;
                            bool shouldPulse = false;
                            
                            switch (liveService.streamState) {
                              case StreamState.preparing:
                                statusText = 'PREPARING';
                                statusColor = Colors.orange;
                                break;
                              case StreamState.live:
                                statusText = 'LIVE';
                                statusColor = Colors.red;
                                shouldPulse = true;
                                break;
                              case StreamState.stopping:
                                statusText = 'STOPPING';
                                statusColor = Colors.grey;
                                break;
                              case StreamState.error:
                                statusText = 'ERROR';
                                statusColor = Colors.red.shade800;
                                break;
                              default:
                                return const SizedBox.shrink();
                            }
                            
                            return Positioned(
                              top: 16,
                              left: 16,
                              child: shouldPulse
                                  ? AnimatedBuilder(
                                      animation: _pulseAnimation,
                                      builder: (context, child) {
                                        return Transform.scale(
                                          scale: _pulseAnimation.value,
                                          child: _buildStatusBadge(statusText, statusColor),
                                        );
                                      },
                                    )
                                  : _buildStatusBadge(statusText, statusColor),
                            );
                          },
                        ),

                        // Recording Indicator
                        if (_isRecording)
                          Positioned(
                            top: 16,
                            right: 16,
                            child: AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _pulseAnimation.value,
                                  child: _buildStatusBadge('REC', Colors.red),
                                );
                              },
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
                      // Stream Configuration Display
                      Consumer<LiveService>(
                        builder: (context, liveService, child) {
                          final config = liveService.configuration;
                          return GlassCard(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.video_settings),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Stream Configuration',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Quality: ${config.quality.value}'),
                                    Text('Visibility: ${config.visibility.value}'),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Action Buttons Row
                      Row(
                        children: [
                          // Main Go Live Button
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
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Media Capture Buttons
                      Row(
                        children: [
                          // Snapshot Button
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: ThemeService.accentGradient,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: MaterialButton(
                                onPressed: _takeSnapshot,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.camera_alt, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text(
                                      'Snapshot',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          
                          const SizedBox(width: 16),
                          
                          // Video Recording Button
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: _isRecording 
                                  ? LinearGradient(
                                      colors: [Colors.red, Colors.red.shade700],
                                    )
                                  : ThemeService.accentGradient,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: MaterialButton(
                                onPressed: _isRecording ? _stopVideoRecording : _startVideoRecording,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _isRecording ? Icons.stop : Icons.videocam,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _isRecording ? 'Stop' : 'Record',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
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

  void _showStreamSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const StreamSettingsBottomSheet(),
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
    
    try {
      // First create the stream
      final streamCreated = await liveService.createLiveStream();
      if (!streamCreated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create stream: ${liveService.errorMessage ?? "Unknown error"}')),
          );
        }
        return;
      }
      
      // Then start streaming
      final success = await liveService.startStream();
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Live stream started successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to start live stream: ${liveService.errorMessage ?? "Unknown error"}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting stream: $e')),
        );
      }
    }
  }

  void _handleStopStream() async {
    final liveService = Provider.of<LiveService>(context, listen: false);
    await liveService.stopStream();
  }

  void _takeSnapshot() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not ready')),
      );
      return;
    }

    final liveService = Provider.of<LiveService>(context, listen: false);
    final success = await liveService.captureSnapshot(_cameraController!);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Snapshot saved to gallery!' : 'Failed to save snapshot'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _startVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not ready')),
      );
      return;
    }

    final liveService = Provider.of<LiveService>(context, listen: false);
    final success = await liveService.startVideoRecording(_cameraController!);
    
    if (success) {
      setState(() {
        _isRecording = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video recording started'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start video recording'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _stopVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    final liveService = Provider.of<LiveService>(context, listen: false);
    final success = await liveService.stopVideoRecording(_cameraController!);
    
    setState(() {
      _isRecording = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Video saved to gallery!' : 'Failed to save video'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  String _getButtonText(StreamState state) {
    switch (state) {
      case StreamState.idle:
        return 'Go Live';
      case StreamState.preparing:
      case StreamState.stopping:
        return 'Loading...';
      case StreamState.live:
        return 'Stop Live';
      case StreamState.error:
        return 'Retry';
    }
  }

  Widget _buildStatusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 1,
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
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class StreamSettingsBottomSheet extends StatefulWidget {
  const StreamSettingsBottomSheet({super.key});

  @override
  State<StreamSettingsBottomSheet> createState() => _StreamSettingsBottomSheetState();
}

class _StreamSettingsBottomSheetState extends State<StreamSettingsBottomSheet> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late StreamQuality _selectedQuality;
  late StreamVisibility _selectedVisibility;
  late StreamStatus _selectedStatus;

  @override
  void initState() {
    super.initState();
    final liveService = Provider.of<LiveService>(context, listen: false);
    final config = liveService.configuration;
    
    _titleController = TextEditingController(text: config.title ?? '');
    _descriptionController = TextEditingController(text: config.description ?? '');
    _selectedQuality = config.quality;
    _selectedVisibility = config.visibility;
    _selectedStatus = config.status;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stream Settings',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          
          // Title
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Stream Title',
              hintText: 'Enter stream title (optional)',
              border: OutlineInputBorder(),
            ),
            maxLength: 100,
          ),
          const SizedBox(height: 16),
          
          // Description
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Enter stream description (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            maxLength: 500,
          ),
          const SizedBox(height: 16),
          
          // Quality Dropdown
          DropdownButtonFormField<StreamQuality>(
            value: _selectedQuality,
            decoration: const InputDecoration(
              labelText: 'Stream Quality',
              border: OutlineInputBorder(),
            ),
            items: StreamQuality.values.map((quality) {
              return DropdownMenuItem(
                value: quality,
                child: Text(quality.value),
              );
            }).toList(),
            onChanged: (quality) {
              if (quality != null) {
                setState(() {
                  _selectedQuality = quality;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          
          // Visibility Dropdown
          DropdownButtonFormField<StreamVisibility>(
            value: _selectedVisibility,
            decoration: const InputDecoration(
              labelText: 'Visibility',
              border: OutlineInputBorder(),
            ),
            items: StreamVisibility.values.map((visibility) {
              return DropdownMenuItem(
                value: visibility,
                child: Text(visibility.value),
              );
            }).toList(),
            onChanged: (visibility) {
              if (visibility != null) {
                setState(() {
                  _selectedVisibility = visibility;
                });
              }
            },
          ),
          const SizedBox(height: 24),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveSettings,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _saveSettings() {
    final liveService = Provider.of<LiveService>(context, listen: false);
    
    final config = StreamConfiguration(
      title: _titleController.text.isEmpty ? null : _titleController.text,
      description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
      quality: _selectedQuality,
      visibility: _selectedVisibility,
      status: _selectedStatus,
    );
    
    liveService.updateConfiguration(config);
    Navigator.pop(context);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved!'),
        backgroundColor: Colors.green,
      ),
    );
  }
}