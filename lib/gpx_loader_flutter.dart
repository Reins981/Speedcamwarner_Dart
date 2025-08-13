import 'package:flutter/services.dart' show rootBundle;

Future<String> loadGpxImpl(String path) async {
  return rootBundle.loadString(path);
}
