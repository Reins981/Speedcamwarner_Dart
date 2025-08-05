/// Simple 2D point used by geometry helpers.
class Point {
  double x;
  double y;

  Point([this.x = 0.0, this.y = 0.0]);

  /// Returns a new [Point] representing the sum of this point and [other].
  Point add(Point other) => Point(x + other.x, y + other.y);
}
