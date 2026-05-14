import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../firebase_options.dart';
import '../screens/agent_analysis_screen.dart';

// Top-level background handler. Must be a top-level (not class method) function
// annotated with @pragma('vm:entry-point') so the Flutter engine can find it
// when the app is in the background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // The OS already displays the notification automatically when `notification`
  // is in the payload — we don't need to do anything here. Re-initializing
  // Firebase is required because the background isolate is separate.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[NOTIFY-BG] Received background message: ${message.messageId}');
}

/// Singleton manager for FCM. Initialize once after the user signs in.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Global navigator key — must be passed to MaterialApp(navigatorKey: ...)
  /// so notification taps can navigate without needing a BuildContext.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  bool _initialized = false;

  /// Idempotent — safe to call multiple times. Subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;

      // Request notification permission (iOS shows OS dialog; Android 13+ also)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[NOTIFY] Permission status: ${settings.authorizationStatus}');

      // Background message handler — must be registered before any listeners.
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Foreground messages — show in-app SnackBar
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Tap on a notification while app is in the background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // App launched from a terminated state via a notification tap
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        // Delay so the navigator is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationTap(initialMessage);
        });
      }

      // Fetch + register token; listen for refresh
      final token = await messaging.getToken();
      if (token != null) {
        debugPrint('[NOTIFY] FCM token: ${token.substring(0, 12)}…');
        await _registerToken(token);
      }
      messaging.onTokenRefresh.listen((t) {
        debugPrint('[NOTIFY] Token refreshed');
        _registerToken(t);
      });
    } catch (e, st) {
      debugPrint('[NOTIFY] initialize() failed: $e\n$st');
    }
  }

  /// Resets state so a future sign-in re-runs initialize.
  void reset() => _initialized = false;

  Future<void> _registerToken(String token) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) {
        debugPrint('[NOTIFY] No auth token — skipping FCM token registration');
        return;
      }
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/user-settings/fcm-token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('[NOTIFY] FCM token registered → ${response.statusCode}');
    } catch (e) {
      debugPrint('[NOTIFY] _registerToken error: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    final title = notification.title ?? '';
    final body = notification.body ?? '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 6),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
              ),
            ],
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: const Color(0xFF3B82F6),
          onPressed: () => _handleNotificationTap(message),
        ),
      ),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final screen = data['screen']?.toString() ?? 'home';
    debugPrint('[NOTIFY] Tap → screen=$screen, data=$data');

    final state = navigatorKey.currentState;
    if (state == null) return;

    switch (screen) {
      case 'agent':
        state.push(
          MaterialPageRoute(builder: (_) => const AgentAnalysisScreen()),
        );
        break;
      case 'home':
      default:
        state.popUntil((route) => route.isFirst);
        break;
    }
  }
}
