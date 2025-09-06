import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import '../config.dart';

class User {
  final int? id;
  final String username;
  final String role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  User({
    this.id,
    required this.username,
    required this.role,
    this.createdAt,
    this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      role: json['role'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }
}

class UserManagementService extends ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  final _dio = Dio();

  List<User> _users = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<User> get users => _users;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<String?> _getAuthToken() async {
    return await _secureStorage.read(key: 'app_session');
  }

  Options _getAuthHeaders(String token) {
    return Options(
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  Future<bool> createUser(String username, String password) async {
    _setLoading(true);
    
    try {
      final token = await _getAuthToken();
      if (token == null) {
        _handleError('Authentication token not found');
        return false;
      }

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/users',
        data: {
          'username': username,
          'password': password,
        },
        options: _getAuthHeaders(token),
      );

      if (response.statusCode == 200) {
        _clearError();
        await loadUsers(); // Reload users list
        return true;
      } else {
        _handleError('Failed to create user');
        return false;
      }
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 409) {
        _handleError('Username already exists');
      } else {
        _handleError('Failed to create user: $e');
      }
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> loadUsers() async {
    _setLoading(true);
    
    try {
      final token = await _getAuthToken();
      if (token == null) {
        _handleError('Authentication token not found');
        return false;
      }

      final response = await _dio.get(
        '${AppConfig.backendBaseUrl}/users',
        options: _getAuthHeaders(token),
      );

      if (response.statusCode == 200) {
        final usersData = response.data['users'] as List;
        _users = usersData.map((userData) => User.fromJson(userData)).toList();
        _clearError();
        notifyListeners();
        return true;
      } else {
        _handleError('Failed to load users');
        return false;
      }
    } catch (e) {
      _handleError('Failed to load users: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updateUserPassword(int userId, String newPassword) async {
    _setLoading(true);
    
    try {
      final token = await _getAuthToken();
      if (token == null) {
        _handleError('Authentication token not found');
        return false;
      }

      final response = await _dio.put(
        '${AppConfig.backendBaseUrl}/users/$userId',
        data: {
          'password': newPassword,
        },
        options: _getAuthHeaders(token),
      );

      if (response.statusCode == 200) {
        _clearError();
        return true;
      } else {
        _handleError('Failed to update user');
        return false;
      }
    } catch (e) {
      _handleError('Failed to update user: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteUser(int userId) async {
    _setLoading(true);
    
    try {
      final token = await _getAuthToken();
      if (token == null) {
        _handleError('Authentication token not found');
        return false;
      }

      final response = await _dio.delete(
        '${AppConfig.backendBaseUrl}/users/$userId',
        options: _getAuthHeaders(token),
      );

      if (response.statusCode == 200) {
        _clearError();
        await loadUsers(); // Reload users list
        return true;
      } else {
        _handleError('Failed to delete user');
        return false;
      }
    } catch (e) {
      _handleError('Failed to delete user: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _handleError(String error) {
    _errorMessage = error;
    notifyListeners();
    
    if (kDebugMode) {
      print('UserManagementService Error: $error');
    }
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    _clearError();
  }
}