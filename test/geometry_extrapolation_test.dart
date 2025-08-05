import 'package:test/test.dart';
import '../lib/rect.dart';
import '../lib/point.dart';

void main() {
  test('intersection and point checks', () {
    final r1 = Rect(pt1: Point(0, 0), pt2: Point(2, 2));
    final r2 = Rect(pt1: Point(1, 1), pt2: Point(3, 3));
    final inter = intersectRectangle(r1, r2);
    expect(inter.left, 1);
    expect(pointInIntersectedRect(r1, r2, 1.5, 1.5), isTrue);
  });

  test('extrapolate and sort', () {
    final r1 = Rect(pt1: Point(0, 0), pt2: Point(1, 1));
    final r2 = Rect(pt1: Point(1, 1), pt2: Point(2, 2));
    final ex = extrapolateRectangle(r1, r2);
    expect(ex.left, 2);
    final sorted = sortRectangles([r2, r1]);
    expect(sorted.first.left, 0);
  });
}
