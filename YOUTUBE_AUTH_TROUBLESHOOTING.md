# YouTube Authentication Troubleshooting

## Common Error: PlatformException(sign_in_failed, com.google.android.gms.common.api.ApiException: 10:, null, null)

This error indicates a Google Sign-In API error with code 10 (DEVELOPER_ERROR).

### Root Causes & Solutions

#### 1. OAuth Configuration Mismatch
**Problem**: Redirect URI inconsistency between app config and Google Cloud Console.
**Solution**: Ensure all configurations match:
- `press_connect/assets/config.json` → `redirectUri`
- `backend/local.config.json` → `oauth.redirectUri`
- Android: `android/app/src/main/AndroidManifest.xml` → intent filter scheme
- iOS: `ios/Runner/Info.plist` → CFBundleURLSchemes

#### 2. Missing SHA-1 Fingerprint (Android)
**Problem**: SHA-1 fingerprint not added to Google Cloud Console.
**Solution**: 
```bash
# For debug builds
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

# Add the SHA-1 to Google Cloud Console > Credentials > OAuth 2.0 Client ID
```

#### 3. Package Name Mismatch
**Problem**: Package name in Google Cloud Console doesn't match app.
**Solution**: Verify package name in:
- `android/app/src/main/AndroidManifest.xml` (package attribute)
- Google Cloud Console OAuth client configuration

#### 4. Missing Client Secret (Backend)
**Problem**: OAuth client secret not configured for server-side token exchange.
**Solution**: Add `clientSecret` to `backend/local.config.json`:
```json
{
  "oauth": {
    "clientId": "YOUR_CLIENT_ID",
    "clientSecret": "YOUR_CLIENT_SECRET",
    "redirectUri": "com.example.press_connect:/oauth2redirect"
  }
}
```

#### 5. iOS URL Scheme Not Configured
**Problem**: iOS app can't handle OAuth redirects.
**Solution**: Add URL scheme to `ios/Runner/Info.plist`:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.example.press_connect</string>
        </array>
    </dict>
</array>
```

### Testing the Fix

1. Clean and rebuild the app
2. Try YouTube authentication
3. Check debug logs for detailed error information
4. Verify Google Cloud Console configuration matches app configuration

### Debug Information

The app now includes enhanced debugging. In debug mode, you'll see:
- Google Sign-In initialization status
- OAuth client ID being used
- Scopes requested
- Detailed error information with troubleshooting hints