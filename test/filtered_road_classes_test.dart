import 'package:test/test.dart';
import 'package:workspace/filtered_road_classes.dart';

void main() {
  test('hasValue recognises defined classes', () {
    expect(FilteredRoadClass.hasValue(10000), isTrue);
    expect(FilteredRoadClass.hasValue(9999), isFalse);
  });
}
