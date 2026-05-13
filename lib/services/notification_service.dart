import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../screens/recommendations_screen.dart';
import '../screens/trends_screen.dart';

/// Top-level background handler for FCM. MUST be a top-level function (not a
/// method or closure) so the Flutter engine can spin up a background isolate
/// when the app is fully terminated and dispatch the message to it.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Nothing to do in the background here — Android automatically shows the
  // notification using the `notification` payload. We just log so it's visible
  // during development.
  debugPrint('[NOTIFY-BG] Background message: ${message.messageId}, '
      'data: ${message.data}');
}

/// Singleton service that owns all FCM concerns:
///   • requesting Android 13+ POST_NOTIFICATIONS permission
///   • fetching the device's FCM token and registering it with the backend
///   • listening for token rotation (Google rotates tokens periodically)
///   • routing notification taps to the right screen via a global navigator key
///
/// Should be initialized AFTER Firebase Auth confirms a signed-in user — so
/// the backend can associate the token with the right userId.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Global navigator key set on MaterialApp. Lets us push routes from
  /// notification handlers that run outside any widget context.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  bool _initialized = false;

  /// Call exactly once per signed-in session (e.g. from HomeDashboard.initState
  /// or right after sign-in completes). Safe to call multiple times — guarded.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final messaging = FirebaseMessaging.instance;

    // Register the top-level background handler BEFORE anything else
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Ask for Android 13+ runtime permission. Silently a no-op on older Android.
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[NOTIFY] Permission status: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[NOTIFY] Permission denied — push notifications disabled');
      return;
    }

    // Fetch and register the token
    final token = await messaging.getToken();
    if (token != null) {
      debugPrint('[NOTIFY] FCM token: ${token.substring(0, 16)}…');
      await _registerToken(token);
    } else {
      debugPrint('[NOTIFY] FCM token was null — registration skipped');
    }

    // Tokens rotate periodically — keep the backend updated
    messaging.onTokenRefresh.listen((newToken) {
      debugPrint('[NOTIFY] Token refreshed: ${newToken.substring(0, 16)}…');
      _registerToken(newToken);
    });

    // Foreground: a system notification doesn't show by default while the app
    // is open, so we surface it ourselves via a snackbar.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Tap while app in background (resumed) → route to the right screen
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Tap while app was terminated → app launches with the initial message
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      // Defer routing until the first frame so navigatorKey.currentState exists
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNotificationTap(initial);
      });
    }

    debugPrint('[NOTIFY] Notification service initialized');
  }

  Future<void> _registerToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[NOTIFY] No signed-in user — token not sent to backend');
        return;
      }
      final idToken = await user.getIdToken();
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/user-settings/fcm-token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('[NOTIFY] Token register → status: ${response.statusCode}');
    } catch (e) {
      debugPrint('[NOTIFY] _registerToken error: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[NOTIFY-FG] Foreground message: ${message.notification?.title}');
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final notification = message.notification;
    if (notification == null) return;

    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.title ?? '',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            if (notification.body != null) ...[
              const SizedBox(height: 4),
              Text(
                notification.body!,
                style: const TextStyle(color: Color(0xFF94A3B8)),
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
    final screen = message.data['screen'] as String?;
    debugPrint('[NOTIFY] Tap → screen: $screen');
    final navigator = navigatorKey.currentState;
    if (navigator == null || screen == null) return;

    switch (screen) {
      case 'trends':
        navigator.push(MaterialPageRoute(builder: (_) => const TrendsScreen()));
        break;
      case 'recommendations':
        navigator.push(MaterialPageRoute(builder: (_) => const RecommendationsScreen()));
        break;
      case 'home':
        // Summary opens the home banner — pop everything back to the dashboard
        navigator.popUntil((route) => route.isFirst);
        break;
      default:
        debugPrint('[NOTIFY] Unknown screen in data payload: $screen');
    }
  }
}
