import 'dart:io';

Future<String> loadGpxImpl(String path) async {
  return File(path).readAsString();
}
