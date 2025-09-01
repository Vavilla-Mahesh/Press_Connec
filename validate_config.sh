#!/bin/bash

# Configuration Validation Script for YouTube Authentication Fix

echo "🔍 Validating YouTube Authentication Configuration..."
echo "=================================================="

# Function to check if a pattern exists in a file
check_config() {
    local file="$1"
    local pattern="$2"
    local description="$3"
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "✅ $description: FOUND"
        return 0
    else
        echo "❌ $description: NOT FOUND"
        return 1
    fi
}

cd "$(dirname "$0")"

echo ""
echo "🔧 Checking OAuth Configuration Consistency..."
echo "----------------------------------------------"

# Check Flutter config.json
check_config "press_connect/assets/config.json" "com.example.press_connect:/oauth2redirect" "Flutter config redirectUri"

# Check backend config
check_config "backend/local.config.json" "com.example.press_connect:/oauth2redirect" "Backend OAuth redirectUri"
# Client secret is now optional for Android OAuth
if grep -q "clientSecret" "backend/local.config.json" 2>/dev/null; then
    echo "⚠️  Backend OAuth clientSecret: PRESENT (not recommended for Android apps)"
else
    echo "✅ Backend OAuth clientSecret: NOT PRESENT (Android OAuth mode - recommended)"
fi

# Check Android manifest
check_config "press_connect/android/app/src/main/AndroidManifest.xml" 'android:scheme="com.example.press_connect"' "Android manifest URL scheme"
check_config "press_connect/android/app/src/main/AndroidManifest.xml" 'package="com.example.press_connect"' "Android package name"

# Check iOS Info.plist
check_config "press_connect/ios/Runner/Info.plist" "<string>com.example.press_connect</string>" "iOS URL scheme"
check_config "press_connect/ios/Runner/Info.plist" "NSCameraUsageDescription" "iOS camera permission"
check_config "press_connect/ios/Runner/Info.plist" "NSMicrophoneUsageDescription" "iOS microphone permission"

echo ""
echo "🔧 Checking Enhanced Authentication Service..."
echo "--------------------------------------------"

# Check auth service enhancements
check_config "press_connect/lib/services/auth_service.dart" "serverClientId" "GoogleSignIn serverClientId parameter"
check_config "press_connect/lib/services/auth_service.dart" "kDebugMode" "Enhanced debug logging"
check_config "press_connect/lib/services/auth_service.dart" "PlatformException" "Enhanced error handling"

echo ""
echo "🔧 Checking Backend OAuth Implementation..."
echo "-----------------------------------------"

# Check backend OAuth improvements
if grep -q "oauthConfig.clientSecret || null" "backend/src/google.oauth.js" 2>/dev/null; then
    echo "✅ Backend OAuth implementation: UPDATED for Android (optional client secret)"
else
    echo "❌ Backend OAuth implementation: NOT UPDATED for Android"
fi

echo ""
echo "📚 Checking Documentation..."
echo "---------------------------"

check_config "YOUTUBE_AUTH_TROUBLESHOOTING.md" "ApiException: 10" "Troubleshooting guide exists"

echo ""
echo "✨ Validation Complete!"
echo ""
echo "🚀 Next Steps:"
echo "1. Ensure Google Cloud Console OAuth client has the correct:"
echo "   - Package name: com.example.press_connect"
echo "   - SHA-1 fingerprint for your debug/release keystores"
echo "   - Redirect URI: com.example.press_connect:/oauth2redirect"
echo ""
echo "2. ✅ Client secret is no longer required for Android OAuth (more secure)"
echo ""
echo "3. Test the authentication flow on a device/emulator"