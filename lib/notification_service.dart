import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Simple wrapper around [FlutterLocalNotificationsPlugin] used to show
/// alerts when a speed camera is detected.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// Initialize the notification plugin. Should be called during app start.
  static Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);
  }

  /// Display a high priority notification warning about an approaching camera.
  static Future<void> showCameraAlert() async {
    const androidDetails = AndroidNotificationDetails(
      'speedcam_alerts',
      'SpeedCam Alerts',
      channelDescription: 'Notifications for approaching speed cameras',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      0,
      'Speed camera ahead',
      'Stay alert!',
      details,
    );
  }
}
