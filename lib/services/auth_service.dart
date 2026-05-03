import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthResult {
  final User? user;
  final String? errorMessage;
  final bool isSuccess;

  AuthResult._({this.user, this.errorMessage, required this.isSuccess});

  factory AuthResult.success(User user) =>
      AuthResult._(user: user, isSuccess: true);

  factory AuthResult.failure(String message) =>
      AuthResult._(errorMessage: message, isSuccess: false);
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  String? get currentUserId => _auth.currentUser?.uid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    debugPrint('[AUTH] signUp attempt — email: $email, displayName: $displayName');
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await credential.user?.updateDisplayName(displayName.trim());
      debugPrint('[AUTH] signUp success — uid: ${credential.user!.uid}');
      return AuthResult.success(credential.user!);
    } on FirebaseAuthException catch (e) {
      final msg = _mapFirebaseError(e.code);
      debugPrint('[AUTH] signUp failed — code: ${e.code}, message: $msg');
      return AuthResult.failure(msg);
    } catch (e) {
      debugPrint('[AUTH] signUp unexpected error: $e');
      return AuthResult.failure('Something went wrong. Please try again.');
    }
  }

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    debugPrint('[AUTH] signIn attempt — email: $email');
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      debugPrint('[AUTH] signIn success — uid: ${credential.user!.uid}');
      return AuthResult.success(credential.user!);
    } on FirebaseAuthException catch (e) {
      final msg = _mapFirebaseError(e.code);
      debugPrint('[AUTH] signIn failed — code: ${e.code}, message: $msg');
      return AuthResult.failure(msg);
    } catch (e) {
      debugPrint('[AUTH] signIn unexpected error: $e');
      return AuthResult.failure('Something went wrong. Please try again.');
    }
  }

  Future<void> signOut() async {
    debugPrint('[AUTH] signOut — uid: ${_auth.currentUser?.uid}');
    await _auth.signOut();
    debugPrint('[AUTH] signOut complete');
  }

  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final token = await _auth.currentUser?.getIdToken(forceRefresh);
    debugPrint('[AUTH] getIdToken — token length: ${token?.length ?? 0}');
    return token;
  }

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'network-request-failed':
        return 'No internet connection. Check your network.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
