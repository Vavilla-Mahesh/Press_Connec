import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

/// Exception for circuit breaker pattern
class CircuitBreakerException implements Exception {
  final String message;
  CircuitBreakerException(this.message);
  
  @override
  String toString() => 'CircuitBreakerException: $message';
}

/// Circuit breaker states
enum CircuitBreakerState { closed, open, halfOpen }

/// Circuit breaker for preventing cascade failures
class CircuitBreaker {
  final int failureThreshold;
  final Duration timeout;
  final Duration halfOpenTimeout;
  
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  CircuitBreakerState _state = CircuitBreakerState.closed;
  
  CircuitBreaker({
    this.failureThreshold = 5,
    this.timeout = const Duration(minutes: 1),
    this.halfOpenTimeout = const Duration(seconds: 30),
  });
  
  CircuitBreakerState get state => _state;
  int get failureCount => _failureCount;
  
  /// Execute operation with circuit breaker protection
  Future<T> execute<T>(Future<T> Function() operation) async {
    if (_state == CircuitBreakerState.open) {
      if (_lastFailureTime != null && 
          DateTime.now().difference(_lastFailureTime!) > timeout) {
        _state = CircuitBreakerState.halfOpen;
        if (kDebugMode) {
          print('Circuit breaker transitioning to half-open');
        }
      } else {
        throw CircuitBreakerException('Circuit breaker is open');
      }
    }
    
    try {
      final result = await operation();
      _onSuccess();
      return result;
    } catch (error) {
      _onFailure();
      throw error;
    }
  }
  
  void _onSuccess() {
    _failureCount = 0;
    _state = CircuitBreakerState.closed;
    if (kDebugMode) {
      print('Circuit breaker operation succeeded - state: closed');
    }
  }
  
  void _onFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    
    if (_failureCount >= failureThreshold) {
      _state = CircuitBreakerState.open;
      if (kDebugMode) {
        print('Circuit breaker opened after $_failureCount failures');
      }
    }
  }
  
  /// Reset circuit breaker manually
  void reset() {
    _failureCount = 0;
    _lastFailureTime = null;
    _state = CircuitBreakerState.closed;
  }
}

/// Retry configuration options
class RetryOptions {
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final double backoffFactor;
  final bool useJitter;
  final bool Function(Exception)? retryCondition;
  
  const RetryOptions({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffFactor = 2.0,
    this.useJitter = true,
    this.retryCondition,
  });
  
  /// Default retry condition for network operations
  static bool defaultRetryCondition(Exception error) {
    if (error is DioException) {
      // Retry on network errors and server errors
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;
        case DioExceptionType.badResponse:
          // Retry on 5xx server errors
          return error.response?.statusCode != null && 
                 error.response!.statusCode! >= 500;
        default:
          return false;
      }
    }
    return false;
  }
}

/// Enhanced retry service with exponential backoff and circuit breaker
class RetryService {
  final Map<String, CircuitBreaker> _circuitBreakers = {};
  
  /// Get or create circuit breaker for a service
  CircuitBreaker _getCircuitBreaker(String serviceName) {
    return _circuitBreakers.putIfAbsent(
      serviceName,
      () => CircuitBreaker(),
    );
  }
  
  /// Execute operation with retry logic and circuit breaker
  Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    String serviceName = 'default',
    RetryOptions options = const RetryOptions(),
  }) async {
    final circuitBreaker = _getCircuitBreaker(serviceName);
    
    return await circuitBreaker.execute(() async {
      return await _retryOperation(operation, options);
    });
  }
  
  /// Internal retry logic with exponential backoff
  Future<T> _retryOperation<T>(
    Future<T> Function() operation,
    RetryOptions options,
  ) async {
    Exception? lastException;
    
    for (int attempt = 1; attempt <= options.maxAttempts; attempt++) {
      try {
        if (kDebugMode && attempt > 1) {
          print('Retry attempt $attempt/${options.maxAttempts}');
        }
        
        return await operation();
      } catch (error) {
        lastException = error is Exception ? error : Exception(error.toString());
        
        // Check if we should retry
        final shouldRetry = options.retryCondition?.call(lastException) ?? 
                           RetryOptions.defaultRetryCondition(lastException);
        
        if (!shouldRetry || attempt == options.maxAttempts) {
          if (kDebugMode) {
            print('Not retrying: shouldRetry=$shouldRetry, attempt=$attempt');
          }
          break;
        }
        
        // Calculate delay with exponential backoff
        final delay = _calculateDelay(attempt, options);
        
        if (kDebugMode) {
          print('Operation failed (attempt $attempt), retrying in ${delay.inMilliseconds}ms: $error');
        }
        
        await Future.delayed(delay);
      }
    }
    
    throw lastException!;
  }
  
  /// Calculate delay with exponential backoff and jitter
  Duration _calculateDelay(int attempt, RetryOptions options) {
    var delay = Duration(
      milliseconds: (options.baseDelay.inMilliseconds * 
                    pow(options.backoffFactor, attempt - 1)).round(),
    );
    
    // Apply maximum delay limit
    if (delay > options.maxDelay) {
      delay = options.maxDelay;
    }
    
    // Add jitter to prevent thundering herd
    if (options.useJitter) {
      final jitter = Random().nextDouble() * 0.1; // 10% jitter
      delay = Duration(
        milliseconds: (delay.inMilliseconds * (1 + jitter)).round(),
      );
    }
    
    return delay;
  }
  
  /// Get circuit breaker state for a service
  CircuitBreakerState getCircuitBreakerState(String serviceName) {
    return _circuitBreakers[serviceName]?.state ?? CircuitBreakerState.closed;
  }
  
  /// Reset circuit breaker for a service
  void resetCircuitBreaker(String serviceName) {
    _circuitBreakers[serviceName]?.reset();
  }
  
  /// Reset all circuit breakers
  void resetAllCircuitBreakers() {
    for (final circuitBreaker in _circuitBreakers.values) {
      circuitBreaker.reset();
    }
  }
}

/// Global retry service instance
final retryService = RetryService();

/// Convenience methods for common operations
extension RetryExtension on Future<T> Function() {
  /// Add retry capability to any async operation
  Future<T> withRetry({
    String serviceName = 'default',
    RetryOptions options = const RetryOptions(),
  }) {
    return retryService.executeWithRetry(
      this,
      serviceName: serviceName,
      options: options,
    );
  }
}

/// Specialized retry options for different scenarios
class RetryPresets {
  static const apiCall = RetryOptions(
    maxAttempts: 3,
    baseDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 10),
    backoffFactor: 2.0,
    retryCondition: RetryOptions.defaultRetryCondition,
  );
  
  static const streaming = RetryOptions(
    maxAttempts: 5,
    baseDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 5),
    backoffFactor: 1.5,
  );
  
  static const authentication = RetryOptions(
    maxAttempts: 2,
    baseDelay: Duration(seconds: 2),
    maxDelay: Duration(seconds: 5),
    backoffFactor: 2.0,
    retryCondition: (error) {
      if (error is DioException) {
        // Don't retry on 401/403 errors (authentication issues)
        return error.response?.statusCode != 401 && 
               error.response?.statusCode != 403;
      }
      return true;
    },
  );
  
  static const analytics = RetryOptions(
    maxAttempts: 2,
    baseDelay: Duration(seconds: 3),
    maxDelay: Duration(seconds: 10),
    backoffFactor: 2.0,
  );
}