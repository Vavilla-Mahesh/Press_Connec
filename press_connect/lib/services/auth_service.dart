import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dio/dio.dart';
import '../config.dart';

enum AuthState {
  initial,
  appAuthenticated,
  youtubeAuthenticated,
  loading,
  error
}

enum UserRole {
  admin,
  user
}

class AuthService extends ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  final _dio = Dio();
  
  AuthState _authState = AuthState.initial;
  String? _errorMessage;
  GoogleSignInAccount? _googleUser;
  UserRole? _userRole;
  String? _username;
  int? _userId;
  
  AuthState get authState => _authState;
  String? get errorMessage => _errorMessage;
  GoogleSignInAccount? get googleUser => _googleUser;
  UserRole? get userRole => _userRole;
  String? get username => _username;
  int? get userId => _userId;
  
  bool get isAppAuthenticated => _authState == AuthState.appAuthenticated || 
                                 _authState == AuthState.youtubeAuthenticated;
  bool get isYouTubeAuthenticated => _authState == AuthState.youtubeAuthenticated;
  bool get isAdmin => _userRole == UserRole.admin;
  bool get requiresYouTubeAuth => isAdmin && _authState == AuthState.appAuthenticated;

  GoogleSignIn? _googleSignIn;

  AuthService() {
    _initializeGoogleSignIn();
    _checkAuthState();
  }

  void _initializeGoogleSignIn() {
    try {
      _googleSignIn = GoogleSignIn(
        clientId: AppConfig.googleClientId,
        scopes: AppConfig.youtubeScopes,
        serverClientId: AppConfig.googleClientId, // Ensure server-side auth code
      );
      if (kDebugMode) {
        print('GoogleSignIn initialized with clientId: ${AppConfig.googleClientId}');
        print('Scopes: ${AppConfig.youtubeScopes}');
      }
    } catch (e) {
      _handleError('Failed to initialize Google Sign In: $e');
    }
  }

  Future<void> _checkAuthState() async {
    try {
      final appAuth = await _secureStorage.read(key: 'app_authenticated');
      final youtubeAuth = await _secureStorage.read(key: 'youtube_authenticated');
      final roleStr = await _secureStorage.read(key: 'user_role');
      final storedUsername = await _secureStorage.read(key: 'username');
      final userIdStr = await _secureStorage.read(key: 'user_id');
      
      if (roleStr != null) {
        _userRole = roleStr == 'admin' ? UserRole.admin : UserRole.user;
      }
      
      if (storedUsername != null) {
        _username = storedUsername;
      }
      
      if (userIdStr != null) {
        _userId = int.tryParse(userIdStr);
      }
      
      if (youtubeAuth == 'true') {
        _authState = AuthState.youtubeAuthenticated;
      } else if (appAuth == 'true') {
        _authState = AuthState.appAuthenticated;
      } else {
        _authState = AuthState.initial;
      }
      notifyListeners();
    } catch (e) {
      _handleError('Failed to check authentication state: $e');
    }
  }

  Future<bool> loginWithCredentials(String username, String password) async {
    _setLoading();
    
    try {
      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/auth/app-login',
        data: {
          'username': username,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final userData = response.data['user'];
        _username = userData['username'];
        _userId = userData['id'];
        _userRole = userData['role'] == 'admin' ? UserRole.admin : UserRole.user;
        
        await _secureStorage.write(key: 'app_authenticated', value: 'true');
        await _secureStorage.write(key: 'app_session', value: response.data['token'] ?? '');
        await _secureStorage.write(key: 'user_role', value: userData['role']);
        await _secureStorage.write(key: 'username', value: userData['username']);
        if (userData['id'] != null) {
          await _secureStorage.write(key: 'user_id', value: userData['id'].toString());
        }
        
        _authState = AuthState.appAuthenticated;
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        _handleError('Invalid credentials');
        return false;
      }
    } catch (e) {
      _handleError('Login failed: $e');
      return false;
    }
  }

  Future<bool> connectYouTube() async {
    if (_googleSignIn == null) {
      _handleError('Google Sign In not initialized');
      return false;
    }

    _setLoading();

    try {
      // Sign out first to ensure fresh authentication
      await _googleSignIn!.signOut();
      
      if (kDebugMode) {
        print('Starting Google Sign In...');
      }
      
      final GoogleSignInAccount? account = await _googleSignIn!.signIn();
      if (account == null) {
        _handleError('YouTube authentication cancelled');
        return false;
      }
      
      if (kDebugMode) {
        print('Google Sign In successful for: ${account.email}');
      }
      
      // Use the serverAuthCode from the account object (not from auth)
      final String? serverAuthCode = account.serverAuthCode;
      if (serverAuthCode == null) {
        _handleError('Failed to get server auth code');
        return false;
      }
      
      if (kDebugMode) {
        print('Server auth code obtained, exchanging with backend...');
      }

      // Exchange server auth code with backend
      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/auth/exchange',
        data: {
          'serverAuthCode': serverAuthCode,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer ${await _secureStorage.read(key: 'app_session')}',
          },
        ),
      );

      if (response.statusCode == 200) {
        await _secureStorage.write(key: 'youtube_authenticated', value: 'true');
        _googleUser = account;
        _authState = AuthState.youtubeAuthenticated;
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        _handleError('Failed to exchange YouTube authentication');
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('YouTube authentication error details: $e');
        if (e.toString().contains('PlatformException')) {
          print('This appears to be a Google Play Services or OAuth configuration error.');
          print('Check: 1) SHA-1 fingerprint in Google Cloud Console');
          print('       2) Package name matches in Google Cloud Console');
          print('       3) OAuth redirect URI configuration');
        }
      }
      _handleError('YouTube authentication failed: $e');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _googleSignIn?.signOut();
      await _secureStorage.deleteAll();
      
      _googleUser = null;
      _authState = AuthState.initial;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _handleError('Logout failed: $e');
    }
  }

  void _setLoading() {
    _authState = AuthState.loading;
    _errorMessage = null;
    notifyListeners();
  }

  void _handleError(String error) {
    _authState = AuthState.error;
    _errorMessage = error;
    notifyListeners();
    
    if (kDebugMode) {
      print('AuthService Error: $error');
    }
  }

  void clearError() {
    if (_authState == AuthState.error) {
      _authState = AuthState.initial;
      _errorMessage = null;
      notifyListeners();
    }
  }
}