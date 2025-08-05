import 'dart:convert';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:path/path.dart' as p;

import 'logger.dart';

/// Constants mirroring the Python ``ServiceAccount`` module.
const String FILE_ID = '1T-Frq3_M-NaGMenIZpTHjrjGusBgoKgE';
const String FILENAME = 'python/service_account/cameras.json';

const _serviceAccountJson = 'python/service_account/osmwarner-01bcd4dc2dd3.json';
const _scopes = [drive.DriveApi.driveScope];

/// Build an authenticated HTTP client for the Google Drive API using the
/// service account credentials.
Future<AutoRefreshingAuthClient> buildDriveFromCredentials() async {
  final file = File(_serviceAccountJson);
  if (!file.existsSync()) {
    throw Exception('Service account file not found: $_serviceAccountJson');
  }
  final credentials = ServiceAccountCredentials.fromJson(
    json.decode(file.readAsStringSync()),
  );
  return clientViaServiceAccount(credentials, _scopes);
}

/// Download ``fileId`` from Google Drive and store it as ``FILENAME``.
Future<String> downloadFileFromGoogleDrive(
    String fileId, AutoRefreshingAuthClient client) async {
  final api = drive.DriveApi(client);
  try {
    final media =
        await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia);
    final data = await media.stream
        .fold<List<int>>([], (buffer, bytes) => buffer..addAll(bytes));
    File(FILENAME)..createSync(recursive: true)..writeAsBytesSync(data);
    return 'success';
  } catch (e) {
    return e.toString();
  } finally {
    client.close();
  }
}

class ServiceAccount {
  static final Logger logger = Logger('ServiceAccount');

  static String basePath =
      p.join(Directory.current.path, 'python', 'service_account');
  static String serviceAccount =
      p.join(basePath, 'osmwarner-01bcd4dc2dd3.json');
  static String folderId = '1VlWuYw_lGeZzrVt5P-dvw8ZzZWSXpaQR';
  static String fileName = p.join(basePath, 'cameras.json');
  static List<String> scopes = [drive.DriveApi.driveScope];
  static String fileId = '1T-Frq3_M-NaGMenIZpTHjrjGusBgoKgE';
  static int requestLimit = 1;
  static Duration timeLimit = const Duration(seconds: 2);

  static Map<String, _RequestRecord> userRequests = {};

  static Future<Map<String, dynamic>> loadServiceAccount() async {
    final content = await File(serviceAccount).readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  static Future<Object> buildDriveFromCredentials() async {
    try {
      final jsonCredentials = await File(serviceAccount).readAsString();
      final accountCredentials =
          ServiceAccountCredentials.fromJson(json.decode(jsonCredentials));
      final client = await clientViaServiceAccount(accountCredentials, scopes);
      return drive.DriveApi(client);
    } on FileSystemException catch (e) {
      return e.toString();
    }
  }

  static bool checkRateLimit(String user) {
    final now = DateTime.now();
    final record = userRequests[user];
    if (record != null) {
      if (now.difference(record.timestamp) <= timeLimit) {
        if (record.count > requestLimit) {
          return false;
        } else {
          userRequests[user] =
              _RequestRecord(record.timestamp, record.count + 1);
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
      String name, double latitude, double longitude) async {
    if (!checkRateLimit('master_user')) {
      logger.printLogLine(
          "Dismiss Camera upload: Rate limit exceeded for user: 'master_user'",
          level: 'WARNING');
      return (false, 'RATE_LIMIT_EXCEEDED');
    }

    final newCamera = {
      'name': name,
      'coordinates': [
        {'latitude': latitude, 'longitude': longitude}
      ]
    };
    logger.printLogLine('Adding new camera: $newCamera');

    Map<String, dynamic> content;
    try {
      final jsonContent = await File(fileName).readAsString();
      content = jsonDecode(jsonContent) as Map<String, dynamic>;
    } on FileSystemException {
      logger.printLogLine(
        'addCameraToJson() failed: $fileName not found!',
        level: 'ERROR',
      );
      return (false, 'CAM_FILE_NOT_FOUND');
    }

    final existingCameras = List<Map<String, dynamic>>.from(
        content['cameras'] as List<dynamic>? ?? []);
    for (final camera in existingCameras) {
      final coords = camera['coordinates'][0] as Map<String, dynamic>;
      if (coords['latitude'] == latitude && coords['longitude'] == longitude) {
        logger.printLogLine(
          'Dismiss Camera upload: Duplicate coordinates detected: '
          '($latitude, $longitude)',
          level: 'WARNING',
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
      String id, String folderId, Object driveOrError,
      {String? uploadFileName}) async {
    if (driveOrError is String) {
      return driveOrError;
    }
    final driveApi = driveOrError as drive.DriveApi;
    final fname = uploadFileName ?? fileName;
    try {
      final file = await driveApi.files.get(id, $fields: 'parents');
      final currentParents = (file.parents ?? []).join(',');
      final media =
          drive.Media(File(fname).openRead(), await File(fname).length());
      final updated = await driveApi.files.update(
        drive.File(),
        id,
        addParents: folderId,
        removeParents: currentParents,
        uploadMedia: media,
      );
      final newId = updated.id;
      logger.printLogLine(
          'Camera upload success: File ID $newId has been moved to folder ID $folderId.');
      return 'success';
    } catch (e) {
      return 'An error occurred: $e';
    }
  }

  static Future<String> downloadFileFromGoogleDrive(
      String id, Object driveOrError) async {
    if (driveOrError is String) {
      return driveOrError;
    }
    final driveApi = driveOrError as drive.DriveApi;

    drive.File fileMeta;
    String filePath;
    try {
      fileMeta = await driveApi.files.get(id, $fields: 'name');
      filePath = p.join(basePath, fileMeta.name!);
    } catch (e) {
      return e.toString();
    }

    try {
      final media = await driveApi.files.get(id,
          downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final saveFile = File(filePath).openWrite();
      await media.stream.pipe(saveFile);
      await saveFile.close();
    } catch (e) {
      return e.toString();
    }

    return 'success';
  }
}

class _RequestRecord {
  final DateTime timestamp;
  final int count;
  _RequestRecord(this.timestamp, this.count);
}

