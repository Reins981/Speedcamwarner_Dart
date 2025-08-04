import 'dart:math';

class Node {
  int id;
  double latitudeStart;
  double longitudeStart;
  double latitudeEnd;
  double longitudeEnd;
  Map<String, dynamic> tags;
  Node? prev;
  Node? next;

  Node({
    required this.id,
    required this.latitudeStart,
    required this.longitudeStart,
    required this.latitudeEnd,
    required this.longitudeEnd,
    Map<String, dynamic>? tags,
    this.prev,
    this.next,
  }) : tags = tags ?? {};
}

class DoubleLinkedListNodes {
  Node? head;
  Node? tail;
  Node? node;

  void appendNode(Node newNode) {
    if (head == null) {
      head = tail = newNode;
    } else {
      newNode.prev = tail;
      tail?.next = newNode;
      tail = newNode;
    }
  }

  Node? matchNode(double latitude, double longitude) {
    List<Node> nodeList = [];
    Node? currentNode = head;

    while (currentNode != null) {
      nodeList.add(currentNode);
      currentNode = currentNode.next;
    }

    return smallestDistanceNode(latitude, longitude, nodeList);
  }

  Node? smallestDistanceNode(
      double latitude, double longitude, List<Node> nodeList) {
    if (nodeList.isEmpty) {
      print('Cannot calculate smallest distance node: Node list is empty');
      return null;
    }

    Node? closestNode;
    double minDistance = double.infinity;

    for (var node in nodeList) {
      double distanceToStart = checkDistanceBetweenTwoPoints(
        latitude,
        longitude,
        node.latitudeStart,
        node.longitudeStart,
      );
      double distanceToEnd = checkDistanceBetweenTwoPoints(
        latitude,
        longitude,
        node.latitudeEnd,
        node.longitudeEnd,
      );

      if (distanceToStart < minDistance) {
        minDistance = distanceToStart;
        closestNode = node;
      }
      if (distanceToEnd < minDistance) {
        minDistance = distanceToEnd;
        closestNode = node;
      }
    }

    return closestNode;
  }

  double checkDistanceBetweenTwoPoints(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double R = 6373.0; // Radius of Earth in km

    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c * 1000; // Convert to meters
  }

  double _toRadians(double degree) {
    return degree * pi / 180;
  }
}
