import 'dart:convert';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart';

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
