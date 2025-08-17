import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show FlutterError, rootBundle;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'logger.dart';

class ServiceAccount {
  static final Logger logger = Logger('ServiceAccount');

  static String basePath = '';
  static String serviceAccount = '';
  static String fileName = '';
  static String folderId = '1VlWuYw_lGeZzrVt5P-dvw8ZzZWSXpaQR';
  static List<String> scopes = [drive.DriveApi.driveScope];
  static String fileId = '1T-Frq3_M-NaGMenIZpTHjrjGusBgoKgE';
  static int requestLimit = 1;
  static Duration timeLimit = const Duration(seconds: 2);

  static Map<String, _RequestRecord> userRequests = {};

  static bool _initialized = false;

  static Future<void> _init() async {
    if (_initialized) return;
    String rootPath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      rootPath = dir.path;
    } catch (_) {
      rootPath = Directory.systemTemp.path;
    }
    basePath = p.join(rootPath, 'python', 'service_account');
    serviceAccount = p.join(basePath, 'osmwarner-01bcd4dc2dd3.json');
    if (fileName.isEmpty) {
      fileName = p.join(basePath, 'cameras.json');
    }
    _initialized = true;
  }

  static Future<void> init() => _init();

  static Future<Map<String, dynamic>> loadServiceAccount() async {
    await _init();
    try {
      final content = await File(serviceAccount).readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } on FileSystemException {
      try {
        final content = await rootBundle
            .loadString('assets/service_account/osmwarner-01bcd4dc2dd3.json');
        return jsonDecode(content) as Map<String, dynamic>;
      } on Exception {
        throw Exception(
            'Service account file not found in assets or file system.');
      }
    }
  }

  /// Build an authenticated HTTP client for the Google Drive API using the
  /// service account credentials.
  static Future<AutoRefreshingAuthClient> buildDriveFromCredentials() async {
    await _init();
    String jsonString;
    final file = File(serviceAccount);
    if (await file.exists()) {
      jsonString = await file.readAsString();
    } else {
      try {
        jsonString = await rootBundle
            .loadString('assets/service_account/osmwarner-01bcd4dc2dd3.json');
      } on Exception {
        throw Exception(
            'Service account file not found in assets or file system.');
      }
    }
    final credentials =
        ServiceAccountCredentials.fromJson(json.decode(jsonString));
    return clientViaServiceAccount(credentials, scopes);
  }

  static bool checkRateLimit(String user) {
    final now = DateTime.now();
    final record = userRequests[user];
    if (record != null) {
      if (now.difference(record.timestamp) <= timeLimit) {
        if (record.count > requestLimit) {
          return false;
        } else {
          userRequests[user] = _RequestRecord(
            record.timestamp,
            record.count + 1,
          );
        }
      } else {
        userRequests[user] = _RequestRecord(now, 1);
      }
    } else {
      userRequests[user] = _RequestRecord(now, 1);
    }
    return true;
  }

  static Future<(bool, String?)> addCameraToJson(
    String name,
    String roadName,
    double latitude,
    double longitude,
  ) async {
    await _init();
    if (!checkRateLimit('master_user')) {
      logger.printLogLine(
        "Dismiss Camera upload: Rate limit exceeded for user: 'master_user'",
        logLevel: 'WARNING',
      );
      return (false, 'RATE_LIMIT_EXCEEDED');
    }

    final newCamera = {
      'name': name,
      'road_name': roadName,
      'coordinates': [
        {'latitude': latitude, 'longitude': longitude},
      ],
    };
    logger.printLogLine('Adding new camera: $newCamera');

    Map<String, dynamic> content;
    try {
      final jsonContent = await File(fileName).readAsString();
      content = jsonDecode(jsonContent) as Map<String, dynamic>;
    } on FileSystemException {
      logger.printLogLine(
        'addCameraToJson() failed: $fileName not found!',
        logLevel: 'ERROR',
      );
      return (false, 'CAM_FILE_NOT_FOUND');
    }

    final existingCameras = List<Map<String, dynamic>>.from(
      content['cameras'] as List<dynamic>? ?? [],
    );
    for (final camera in existingCameras) {
      final coords = camera['coordinates'][0] as Map<String, dynamic>;
      if (coords['latitude'] == latitude && coords['longitude'] == longitude) {
        logger.printLogLine(
          'Dismiss Camera upload: Duplicate coordinates detected: '
          '($latitude, $longitude)',
          logLevel: 'WARNING',
        );
        return (false, 'DUPLICATE_COORDINATES');
      }
    }

    existingCameras.add(newCamera);
    content['cameras'] = existingCameras;
    final encoder = const JsonEncoder.withIndent('    ');
    await File(fileName).writeAsString(encoder.convert(content));
    return (true, null);
  }

  static Future<String> uploadFileToGoogleDrive(
    String id,
    String folderId,
    AutoRefreshingAuthClient client, {
    String? uploadFileName,
  }) async {
    await _init();
    final driveApi = drive.DriveApi(client);
    final fname = uploadFileName ?? fileName;
    try {
      final drive.File file =
          await driveApi.files.get(id, $fields: 'parents') as drive.File;
      final currentParents = (file.parents ?? []).join(',');
      final media = drive.Media(
        File(fname).openRead(),
        await File(fname).length(),
      );
      final updated = await driveApi.files.update(
        drive.File(),
        id,
        addParents: folderId,
        removeParents: currentParents,
        uploadMedia: media,
      );
      final newId = updated.id;
      logger.printLogLine(
        'Camera upload success: File ID $newId has been moved to folder ID $folderId.',
      );
      return 'success';
    } catch (e) {
      return 'An error occurred: $e';
    } finally {
      client.close();
    }
  }

  /// Download `fileId` from Google Drive and store it as [fileName].
  static Future<String> downloadFileFromGoogleDrive(
    String fileId,
    AutoRefreshingAuthClient client,
  ) async {
    await _init();
    final api = drive.DriveApi(client);
    try {
      final drive.Media media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final data = await media.stream.fold<List<int>>(
        [],
        (buffer, bytes) => buffer..addAll(bytes),
      );
      File(fileName)
        ..createSync(recursive: true)
        ..writeAsBytesSync(data);
      return 'success';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }
}

class _RequestRecord {
  final DateTime timestamp;
  final int count;
  _RequestRecord(this.timestamp, this.count);
}
