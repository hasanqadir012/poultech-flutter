import 'package:firebase_auth/firebase_auth.dart';

class UserModel {
  final String uid;
  final String email;
  final String? displayName;

  UserModel({
    required this.uid,
    required this.email,
    this.displayName,
  });

  factory UserModel.fromFirebase(User user) {
    return UserModel(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
    );
  }

  String get firstName {
    if (displayName != null && displayName!.trim().isNotEmpty) {
      return displayName!.trim().split(' ').first;
    }
    return email.split('@').first;
  }
}
