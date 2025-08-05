import 'package:test/test.dart';
import '../lib/road_resolver.dart';

void main() {
  test('resolve max speed and roadname', () {
    final tags = {'maxspeed': '50', 'name': 'Main'};
    final res = resolveRoadnameAndMaxSpeed(tags);
    expect(res.roadName, 'Main');
    expect(res.maxSpeed, 50);
  });

  test('combined tags cache', () {
    final cache = <String, String>{};
    addCombinedTags({'a': 1}, cache);
    expect(checkCombinedTags({'a': 2}, cache), isTrue);
    expect(insideCombinedTags('a', cache), isTrue);
    clearCombinedTags(cache);
    expect(cache.isEmpty, isTrue);
  });
}
