import 'dart:math' as math;

import 'point.dart';

/// Axis-aligned rectangle specified by its bounding coordinates.
class Rect {
  double left = 0.0;
  double top = 0.0;
  double right = 0.0;
  double bottom = 0.0;

  double height = 0.0;
  double width = 0.0;

  String ident = '';
  String rectString = '';

  /// Maximum distance (in tile units) used by [pointsCloseToBorder] when
  /// checking if a point lies close to the rectangle boundary.
  double maxCloseToBorderValue = 0.300;
  double maxCloseToBorderValueLookAhead = 0.200;

  Rect({Point? pt1, Point? pt2, List<double>? pointList}) {
    setPoints(pt1, pt2, pointList);
  }

  /// Dispose of the rectangle by resetting all coordinates. Dart's garbage
  /// collector will reclaim the object but the method mirrors the Python
  /// ``delete_rect`` convenience.
  void deleteRect() {
    left = top = right = bottom = 0.0;
    ident = '';
    rectString = '';
  }

  /// Configure the rectangle using either two corner [Point]s or a list of
  /// four coordinates.
  void setPoints(Point? pt1, Point? pt2, List<double>? pointList) {
    if (pointList != null) {
      if (pointList.isNotEmpty && pointList.length < 4) {
        left = top = right = bottom = 0.0;
        return;
      }
      if (pointList.length == 4) {
        left = pointList[0];
        top = pointList[1];
        right = pointList[2];
        bottom = pointList[3];
        return;
      }
    }

    if (pt1 == null || pt2 == null) {
      left = top = right = bottom = 0.0;
      return;
    }

    left = math.min(pt1.x, pt2.x);
    top = math.min(pt1.y, pt2.y);
    right = math.max(pt1.x, pt2.x);
    bottom = math.max(pt1.y, pt2.y);
  }

  void setRectangleIdent(String ident) => this.ident = ident;
  String getRectangleIdent() => ident;

  void setRectangleString(String rectString) => this.rectString = rectString;
  String getRectangleString() => rectString;

  double rectHeight() {
    height = bottom - top;
    return height;
  }

  double rectWidth() {
    width = right - left;
    return width;
  }

  Point topLeft() => Point(left, top);
  Point bottomRight() => Point(right, bottom);
  Point topRight() => Point(right, top);
  Point bottomLeft() => Point(left, bottom);

  /// Return a new rectangle expanded on all sides by [n] units.
  Rect expandedBy(double n) {
    return Rect(
        pt1: Point(left - n, top - n), pt2: Point(right + n, bottom + n));
  }

  /// Combine this rectangle with [other] and return the smallest rectangle
  /// that fully contains both.
  Rect intersectRectWith(Rect other) {
    final left = math.min(this.left, other.left);
    final right = math.max(this.right, other.right);
    final bottom = math.min(this.bottom, other.bottom);
    final top = math.max(this.top, other.top);
    return Rect(pointList: [left, top, right, bottom]);
  }

  /// Check whether the point `(x, y)` lies inside the rectangle using a
  /// winding algorithm, mirroring the original Python implementation.
  bool pointInRect(double? x, double? y) {
    if (x == null || y == null) return false;
    final rect = [topLeft(), topRight(), bottomLeft(), bottomRight()];
    bool inside = false;
    double pt1x = rect[0].x, pt1y = rect[0].y;
    for (var i = 1; i <= rect.length; i++) {
      final pt2x = rect[i % rect.length].x;
      final pt2y = rect[i % rect.length].y;
      if (y >= math.min(pt1y, pt2y)) {
        if (y <= math.max(pt1y, pt2y)) {
          if (x >= math.min(pt1x, pt2x)) {
            if (x <= math.max(pt1x, pt2x)) {
              if (pt1y != pt2y) {
                inside = !inside;
                if (inside) return inside;
              }
            }
          }
        }
      }
      pt1x = pt2x;
      pt1y = pt2y;
    }
    return inside;
  }

  /// Returns `true` if the point `(x, y)` lies within [maxCloseToBorderValue]
  /// (or [maxCloseToBorderValueLookAhead] when [lookAhead] is true) of any
  /// rectangle edge. When [lookAheadMode] equals
  /// ``"Construction area lookahead"`` the check always returns false.
  bool pointsCloseToBorder(double x, double y,
      {bool lookAhead = false,
      String lookAheadMode = 'Speed Camera lookahead'}) {
    final rect = [topLeft(), topRight(), bottomLeft(), bottomRight()];
    final double maxVal =
        lookAhead ? maxCloseToBorderValueLookAhead : maxCloseToBorderValue;
    double pt1x = rect[0].x, pt1y = rect[0].y;
    for (var i = 1; i <= rect.length; i++) {
      final pt2x = rect[i % rect.length].x;
      final pt2y = rect[i % rect.length].y;
      if ((y - math.min(pt1y, pt2y)).abs() <= maxVal ||
          (y - math.max(pt1y, pt2y)).abs() <= maxVal ||
          (x - math.max(pt1x, pt2x)).abs() <= maxVal ||
          (x - math.min(pt1x, pt2x)).abs() <= maxVal) {
        return true;
      }
      pt1x = pt2x;
      pt1y = pt2y;
    }
    return false;
  }
}

/// Compute the intersection of two rectangles. If they do not overlap an empty
/// rectangle (all zeros) is returned.
Rect intersectRectangle(Rect a, Rect b) {
  final left = math.max(a.left, b.left);
  final top = math.max(a.top, b.top);
  final right = math.min(a.right, b.right);
  final bottom = math.min(a.bottom, b.bottom);
  if (left >= right || top >= bottom) {
    return Rect(pointList: [0, 0, 0, 0]);
  }
  return Rect(pointList: [left, top, right, bottom]);
}

/// Determine whether point ([x], [y]) lies within the intersection of [a] and
/// [b].
bool pointInIntersectedRect(Rect a, Rect b, double x, double y) {
  final r = intersectRectangle(a, b);
  return r.pointInRect(x, y);
}

/// Extrapolate a new rectangle by mirroring the movement from [previous] to
/// [current].  This is a simplistic linear extrapolation used for look‑ahead
/// predictions.
Rect extrapolateRectangle(Rect previous, Rect current) {
  final dx = current.left - previous.left;
  final dy = current.top - previous.top;
  return Rect(
      pt1: Point(current.left + dx, current.top + dy),
      pt2: Point(current.right + dx, current.bottom + dy));
}

/// Check whether the [point] lies inside any rectangle from [rects].
bool checkAllRectangles(Point point, List<Rect> rects) {
  return rects.any((r) => r.pointInRect(point.x, point.y));
}

/// Sort rectangles by area (ascending) and return the sorted list.
List<Rect> sortRectangles(List<Rect> rects) {
  rects.sort((a, b) {
    final areaA = a.rectHeight() * a.rectWidth();
    final areaB = b.rectHeight() * b.rectWidth();
    return areaA.compareTo(areaB);
  });
  return rects;
}
