import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class AppAuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  User? _user;
  bool _isLoading = false;
  String? _errorMessage;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _user != null;
  String? get userId => _user?.uid;

  String get displayName {
    if (_user?.displayName != null && _user!.displayName!.trim().isNotEmpty) {
      return _user!.displayName!.trim().split(' ').first;
    }
    return _user?.email?.split('@').first ?? 'Farmer';
  }

  AppAuthProvider() {
    _authService.authStateChanges.listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    _setLoading(true);
    clearError();
    final result = await _authService.signUp(
      email: email,
      password: password,
      displayName: name,
    );
    _setLoading(false);
    if (!result.isSuccess) {
      _errorMessage = result.errorMessage;
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    clearError();
    final result = await _authService.signIn(email: email, password: password);
    _setLoading(false);
    if (!result.isSuccess) {
      _errorMessage = result.errorMessage;
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> signOut() async {
    await _authService.signOut();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
