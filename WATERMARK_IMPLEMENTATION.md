# Watermark Implementation Guide

This document describes how the watermark functionality has been implemented in the Press Connect application.

## Overview

The watermark feature allows users to overlay a transparent image (watermark) on their live streams, snapshots, and video recordings. The watermark is visible to all viewers on YouTube Live streams.

## Implementation Details

### 1. Watermark Service (`lib/services/watermark_service.dart`)

The `WatermarkService` manages watermark configuration:

- **Opacity Control**: Adjustable from 0% to 100%
- **Enable/Disable Toggle**: Quick on/off functionality
- **Asset Path Management**: Handles watermark image paths
- **FFmpeg Filter Generation**: Creates FFmpeg filters for video processing

#### Key Methods:
- `setOpacity(double opacity)`: Sets watermark transparency
- `generateFFmpegFilter()`: Creates FFmpeg overlay filter
- `getRTMPWatermarkConfig()`: Returns RTMP broadcaster configuration

### 2. Live Service Integration (`lib/services/live_service.dart`)

The `LiveService` has been enhanced to support watermarks in streaming:

#### Core Features:
- **RTMP Streaming**: Uses `rtmp_broadcaster` package for YouTube Live
- **Watermark Overlay**: Integrates watermark into video stream
- **Snapshot with Watermark**: Captures images with watermark applied
- **Recording with Watermark**: Records videos with watermark overlay

#### Key Methods:
- `startStream()`: Starts RTMP stream with watermark support
- `takeSnapshot()`: Captures image with watermark using FFmpeg
- `startRecording(String outputPath)`: Records video with watermark
- `setWatermarkService(WatermarkService watermarkService)`: Links watermark service

### 3. UI Integration (`lib/ui/screens/go_live_screen.dart`)

The Go Live screen provides watermark controls:

#### UI Elements:
- **Watermark Preview**: Shows watermark overlay on camera preview
- **Opacity Slider**: Real-time opacity adjustment
- **Enable/Disable Switch**: Toggle watermark on/off
- **Live Controls**: Snapshot and recording buttons

#### User Experience:
- Watermark appears on camera preview in real-time
- Changes to opacity are immediately visible
- Watermark state is preserved across app sessions

## Technical Implementation

### Watermark in Live Streams

1. **RTMP Configuration**: Watermark settings are applied to RTMP broadcaster
2. **UI Overlay**: Watermark is rendered in the camera preview
3. **Stream Capture**: The UI overlay is captured as part of the video stream
4. **YouTube Delivery**: Watermarked video is streamed to YouTube Live

### Watermark in Snapshots

1. **Camera Capture**: Takes photo using camera controller
2. **FFmpeg Processing**: Applies watermark overlay using FFmpeg
3. **Asset Handling**: Copies watermark asset to temporary location
4. **Output Generation**: Creates final image with watermark applied

### Watermark in Recordings

1. **Video Input**: Captures video from camera
2. **Watermark Overlay**: Applies real-time watermark using FFmpeg
3. **Encoding**: Outputs H.264 video with AAC audio
4. **File Output**: Saves to device storage with watermark embedded

## Configuration

### Watermark Asset

- **Location**: `assets/watermarks/default_watermark.png`
- **Format**: PNG with transparency support
- **Recommended Size**: 320x240 pixels or similar ratio
- **Quality**: High resolution for best results

### FFmpeg Filters

The watermark overlay uses FFmpeg video filters:

```
[1:v]scale=320:240,format=rgba,colorchannelmixer=aa=OPACITY[wm];
[0:v][wm]overlay=(W-w)-20:(H-h)-20:enable=1
```

- Scales watermark to 320x240 pixels
- Applies opacity based on user setting
- Positions watermark in bottom-right corner with 20px margin

### Platform Support

- **iOS**: Uses `avfoundation` input format
- **Android**: Uses `android_camera` input format  
- **Desktop**: Uses `v4l2` input format (Linux)

## Error Handling

### Graceful Degradation

1. **FFmpeg Failure**: Falls back to regular streaming without watermark
2. **Asset Loading**: Uses default image if custom watermark fails
3. **Permission Issues**: Shows user-friendly error messages
4. **Network Problems**: Maintains local preview functionality

### Logging

Debug logging is available in development mode:

```dart
if (kDebugMode) {
  print('Watermark streaming started with config: $config');
}
```

## Performance Considerations

### Optimization Strategies

1. **Asset Caching**: Watermark assets are cached in temporary storage
2. **FFmpeg Presets**: Uses optimized encoding presets for mobile
3. **Resolution Scaling**: Watermarks are scaled appropriately
4. **Memory Management**: Proper cleanup of resources

### Mobile Compatibility

- **Encoding**: Uses hardware-accelerated encoding when available
- **Bitrate Control**: Optimized for mobile network conditions
- **Battery Usage**: Efficient processing to minimize battery drain

## Usage Instructions

### For Developers

1. **Service Setup**: Initialize `WatermarkService` in app providers
2. **UI Integration**: Connect watermark controls to service
3. **Live Service**: Link watermark service to live streaming
4. **Asset Management**: Ensure watermark assets are properly bundled

### For Users

1. **Enable Watermark**: Toggle the watermark switch in settings
2. **Adjust Opacity**: Use slider to set desired transparency
3. **Live Streaming**: Watermark appears automatically in stream
4. **Snapshots/Recording**: Watermark is embedded in captured media

## Future Enhancements

### Planned Features

1. **Custom Watermarks**: Support for user-uploaded watermark images
2. **Positioning Options**: Multiple watermark placement options
3. **Animation Effects**: Animated watermark overlays
4. **Multiple Watermarks**: Support for multiple simultaneous watermarks
5. **Template System**: Pre-designed watermark templates

### Technical Improvements

1. **Hardware Acceleration**: Better GPU utilization
2. **Streaming Optimization**: Lower latency watermark processing
3. **Quality Enhancement**: Better compression with watermarks
4. **Platform Extensions**: Enhanced platform-specific features

## Troubleshooting

### Common Issues

1. **Watermark Not Visible**: Check if watermark is enabled and opacity > 0
2. **Performance Issues**: Reduce watermark size or lower stream quality
3. **FFmpeg Errors**: Ensure FFmpeg dependencies are properly installed
4. **Asset Loading**: Verify watermark image exists in assets folder

### Debug Information

Use the `getStreamInfo()` method to check watermark status:

```dart
final streamInfo = liveService.getStreamInfo();
print('Watermark enabled: ${streamInfo['hasWatermark']}');
```

## Dependencies

### Required Packages

- `rtmp_broadcaster: ^2.3.4` - RTMP streaming functionality
- `ffmpeg_kit_flutter_new: ^3.2.0` - Video processing and watermark overlay
- `camera: ^0.10.5+9` - Camera capture functionality
- `path_provider: ^2.1.3` - File system access for temporary files
- `image_gallery_saver: ^2.0.3` - Saving media to device gallery

### Platform Requirements

- **iOS**: iOS 11.0+ for camera and video processing features
- **Android**: API Level 21+ for camera and FFmpeg functionality
- **Permissions**: Camera, microphone, and storage permissions required