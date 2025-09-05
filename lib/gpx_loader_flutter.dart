import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;

/// Load a GPX file from either the bundled assets or an arbitrary file path.
///
/// The original Flutter implementation only supported loading from the
/// application bundle via [rootBundle].  To allow users to pick GPX files from
/// their device storage we first attempt to load the file as an asset and, if
/// that fails, fall back to reading from the local filesystem.
Future<String> loadGpxImpl(String path) async {
  try {
    return await rootBundle.loadString(path);
  } catch (_) {
    return File(path).readAsString();
  }
}
