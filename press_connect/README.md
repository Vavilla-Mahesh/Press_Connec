# Press Connect

A Flutter-based live streaming application for YouTube broadcasting.

## Features

- **Landscape-Only Orientation**: The app is designed exclusively for landscape mode to provide the best streaming experience
- **YouTube Live Streaming**: Stream directly to your YouTube channel via RTMP
- **Camera Controls**: Switch between front and rear cameras during streaming
- **Real-time Preview**: Live camera preview with proper orientation handling
- **Professional Controls**: Watermarks, quality settings, and streaming controls

## Orientation Handling

This application is configured to run **exclusively in landscape mode**:

- All screens are optimized for landscape viewing
- Camera preview maintains proper aspect ratio without rotation artifacts
- YouTube live stream output is native landscape (1920x1080)
- No portrait mode support to ensure consistent streaming quality

## Getting Started

1. Configure your YouTube API credentials in `assets/config.json`
2. Set up your backend server for authentication
3. Build and run the application

## Configuration

See `CONFIGURATION.md` for detailed setup instructions.
