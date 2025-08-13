import 'gpx_loader_io.dart' if (dart.library.ui) 'gpx_loader_flutter.dart';

Future<String> loadGpx(String path) => loadGpxImpl(path);
