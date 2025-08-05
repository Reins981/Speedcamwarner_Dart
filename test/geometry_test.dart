import 'package:test/test.dart';

import 'package:workspace/point.dart';
import 'package:workspace/rect.dart';

void main() {
  group('Point and Rect', () {
    test('point inside rectangle', () {
      final rect = Rect(pt1: Point(0, 0), pt2: Point(10, 10));
      expect(rect.pointInRect(5, 5), isTrue);
      expect(rect.pointInRect(15, 5), isFalse);
    });

    test('points close to border', () {
      final rect = Rect(pt1: Point(0, 0), pt2: Point(10, 10));
      // point near left border
      expect(rect.pointsCloseToBorder(0.05, 5), isTrue);
      // far from border
      expect(rect.pointsCloseToBorder(5, 5), isFalse);
    });

    test('expanded and intersect', () {
      final r1 = Rect(pt1: Point(0, 0), pt2: Point(5, 5));
      final r2 = r1.expandedBy(2);
      expect(r2.left, equals(-2));
      expect(r2.right, equals(7));
      final r3 = Rect(pt1: Point(3, 3), pt2: Point(6, 6));
      final r4 = r1.intersectRectWith(r3);
      expect(r4.left, equals(0));
      expect(r4.right, equals(6));
      expect(r4.bottom, equals(5));
    });
  });
}
