import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../lib/service_account.dart';

void main() {
  group('ServiceAccount', () {
    test('checkRateLimit enforces request limit', () {
      ServiceAccount.userRequests.clear();
      expect(ServiceAccount.checkRateLimit('user'), isTrue);
      expect(ServiceAccount.checkRateLimit('user'), isFalse);
    });

    test('addCameraToJson adds and rejects duplicates', () async {
      final originalFileName = ServiceAccount.fileName;
      final tempDir = Directory.systemTemp.createTempSync();
      final tempFile = File(p.join(tempDir.path, 'cameras.json'));
      await tempFile.writeAsString(jsonEncode({'cameras': []}));
      ServiceAccount.fileName = tempFile.path;
      ServiceAccount.userRequests.clear();

      var res = await ServiceAccount.addCameraToJson('test', 1.0, 2.0);
      expect(res.$1, isTrue);

      ServiceAccount.userRequests.clear();
      res = await ServiceAccount.addCameraToJson('test', 1.0, 2.0);
      expect(res.$1, isFalse);
      expect(res.$2, 'DUPLICATE_COORDINATES');

      final content =
          jsonDecode(await tempFile.readAsString()) as Map<String, dynamic>;
      expect((content['cameras'] as List).length, 1);

      ServiceAccount.fileName = originalFileName;
      tempDir.deleteSync(recursive: true);
    });
  });
}

