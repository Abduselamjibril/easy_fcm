library easy_fcm;

import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Export this so the user doesn't need to import firebase_messaging manually
export 'package:firebase_messaging/firebase_messaging.dart' show RemoteMessage;

// --- BACKGROUND HANDLER (Top Level) ---
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("EasyFCM: Background Message ID: ${message.messageId}");
}

class EasyFCM {
  // Singleton Pattern
  static final EasyFCM _instance = EasyFCM._internal();
  factory EasyFCM() => _instance;
  EasyFCM._internal();

  // [FIX] These are now nullable. We wait to initialize them until
  // Firebase.initializeApp() is definitely complete.
  FirebaseMessaging? _messaging;
  FlutterLocalNotificationsPlugin? _localNotifications;

  /// Initialize the EasyFCM Service
  Future<void> initialize({
    // Optional: Pass generated options here.
    // If null, we assume Firebase.initializeApp() was called before.
    FirebaseOptions? firebaseOptions,
    required Function(String?) onTokenReceived,
    required Function(RemoteMessage) onTap,
    String androidIcon = '@mipmap/ic_launcher', // Default Flutter Icon
  }) async {
    // 1. Initialize Firebase App FIRST
    if (Firebase.apps.isEmpty) {
      if (firebaseOptions != null) {
        await Firebase.initializeApp(options: firebaseOptions);
      } else {
        await Firebase.initializeApp();
      }
    }

    // 2. NOW it is safe to create the instances
    _messaging = FirebaseMessaging.instance;
    _localNotifications = FlutterLocalNotificationsPlugin();

    // 3. Register Background Handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // 4. Request Permissions (Critical for iOS/Android 13+)
    // We use the (!) operator because we know _messaging is now initialized
    NotificationSettings settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      print('EasyFCM: Permission Denied');
      return;
    }

    // 5. Setup Android High Importance Channel (For Foreground Pop-ups)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // id
      'High Importance Notifications', // title
      description: 'This channel is used for important notifications.',
      importance: Importance.max, // This causes the pop-up
    );

    await _localNotifications!
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // 6. Initialize Local Notifications Plugin
    await _localNotifications!.initialize(
      InitializationSettings(
        android: AndroidInitializationSettings(androidIcon),
        iOS: const DarwinInitializationSettings(),
      ),
      // Handle if user taps the Local Notification (Foreground tap)
      onDidReceiveNotificationResponse: (details) {
        print("EasyFCM: Foreground Local Notification Tapped");
      },
    );

    // 7. Get & Monitor Token
    String? token = await _messaging!.getToken();
    onTokenReceived(token);

    _messaging!.onTokenRefresh.listen(onTokenReceived);

    // 8. LISTENERS

    // A. Foreground Listener (The Bridge)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      // If it's a notification, show it manually!
      if (notification != null && android != null) {
        _localNotifications!.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: androidIcon,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
        );
      }
    });

    // B. Background/Terminated Tap
    FirebaseMessaging.onMessageOpenedApp.listen(onTap);

    // C. Check if app opened from Terminated state
    _messaging!.getInitialMessage().then((message) {
      if (message != null) onTap(message);
    });

    print("EasyFCM: Initialized Successfully!");
  }
}
