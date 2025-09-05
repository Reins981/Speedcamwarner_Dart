import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

/// Initializes a simple foreground service so the app can continue
/// running when placed into the background.
class BackgroundService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Configure and start the background service.
  static Future<void> initialize() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'speedcamwarner_service',
        initialNotificationTitle: 'SpeedCamWarner',
        initialNotificationContent: 'Running in background',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(),
    );
    await _service.startService();
  }

  /// Callback executed by the background service.
  static void onStart(ServiceInstance service) {
    if (service is AndroidServiceInstance) {
      service.on('stopService').listen((event) {
        service.stopSelf();
      });
      service.setForegroundNotificationInfo(
        title: 'SpeedCamWarner',
        content: 'Running in background',
      );
    }
  }
}
