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
  dynamic treeGeneratorInstance;

  void appendNode(Node newNode) {
    if (head == null) {
      head = tail = newNode;
    } else {
      newNode.prev = tail;
      tail?.next = newNode;
      tail = newNode;
    }
  }

  void appendNodeData({
    required int nodeId,
    required double latitudeStart,
    required double longitudeStart,
    required double latitudeEnd,
    required double longitudeEnd,
    Map<String, dynamic>? tags,
  }) {
    appendNode(Node(
      id: nodeId,
      latitudeStart: latitudeStart,
      longitudeStart: longitudeStart,
      latitudeEnd: latitudeEnd,
      longitudeEnd: longitudeEnd,
      tags: tags,
    ));
  }

  bool _isRoadNameAvailable(int nodeId) {
    if (treeGeneratorInstance != null) {
      var way = treeGeneratorInstance[nodeId];
      if (treeGeneratorInstance.hasRoadNameAttribute(way) ||
          treeGeneratorInstance.hasRefAttribute(way)) {
        return true;
      }
    }
    return false;
  }

  void setTreeGeneratorInstance(dynamic instance) {
    treeGeneratorInstance = instance;
  }

  void deleteLinkedList() {
    head = null;
    tail = null;
    node = null;
  }

  Node? matchNode(double latitude, double longitude) {
    List<Node> nodeList = [];
    Node? currentNode = head;

    while (currentNode != null) {
      if (_isRoadNameAvailable(currentNode.id)) {
        nodeList.add(currentNode);
      }
      currentNode = currentNode.next;
    }

    node = smallestDistanceNode(latitude, longitude, nodeList);

    if (node == null) {
      print(' No node matched');
      return null;
    }

    return node;
  }

  Node? smallestDistanceNode(
      double latitude, double longitude, List<Node> nodeList) {
    if (nodeList.isEmpty) {
      print(' Cannot calculate smallest distance node: Length of Node list is 0');
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

      if (distanceToStart != -1 && distanceToStart < minDistance) {
        minDistance = distanceToStart;
        closestNode = node;
      }
      if (distanceToEnd != -1 && distanceToEnd < minDistance) {
        minDistance = distanceToEnd;
        closestNode = node;
      }
    }

    if (closestNode != null) {
      print(' Most likely node id is ${closestNode.id}');
    }

    return closestNode;
  }

  double checkDistanceBetweenTwoPoints(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double R = 6373.0;

    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c * 1000;
  }

  double _toRadians(double degree) {
    return degree * pi / 180;
  }

  void setNode(Node? node) {
    this.node = node;
  }

  bool hasNextNode() {
    return node?.next != null;
  }

  Node? getNextNode() {
    return node?.next;
  }

  Node? getNode() {
    return node;
  }

  (int, int, int, Map<String, List<dynamic>>) getAttributesOfSpeedCameras(
      dynamic guiObj) {
    int fixedcamSize = 0;
    int trafficcamSize = 0;
    int mobileCamSize = 0;
    Map<String, List<dynamic>> speedCamDict = {};
    Node? currentNode = head;

    while (currentNode != null) {
      guiObj?.updateGui();
      if (hasHighwayAttribute(currentNode)) {
        if (hasSpeedCam(currentNode)) {
          bool enforcement = true;
          fixedcamSize += 1;
          String fix = 'FIX_$fixedcamSize';
          speedCamDict[fix] = [
            currentNode.latitudeStart,
            currentNode.longitudeStart,
            currentNode.latitudeEnd,
            currentNode.longitudeEnd,
            enforcement,
          ];
        }
      }
      if (hasEnforcementAttribute2(currentNode) &&
          hasTrafficCamEnforcement(currentNode)) {
        bool enforcement = true;
        trafficcamSize += 1;
        String traffic = 'TRAFFIC_$trafficcamSize';
        speedCamDict[traffic] = [
          currentNode.latitudeStart,
          currentNode.longitudeStart,
          currentNode.latitudeEnd,
          currentNode.longitudeEnd,
          enforcement,
        ];
      } else if (hasCrossingAttribute(currentNode) &&
          hasTrafficCamCrossing(currentNode)) {
        bool enforcement = false;
        trafficcamSize += 1;
        String traffic = 'TRAFFIC_$trafficcamSize';
        speedCamDict[traffic] = [
          currentNode.latitudeStart,
          currentNode.longitudeStart,
          currentNode.latitudeEnd,
          currentNode.longitudeEnd,
          enforcement,
        ];
      } else if (hasSpeedCamAttribute(currentNode) &&
          hasTrafficCam(currentNode)) {
        bool enforcement = true;
        trafficcamSize += 1;
        String traffic = 'TRAFFIC_$trafficcamSize';
        speedCamDict[traffic] = [
          currentNode.latitudeStart,
          currentNode.longitudeStart,
          currentNode.latitudeEnd,
          currentNode.longitudeEnd,
          enforcement,
        ];
      } else if (hasDeviceAttribute(currentNode)) {
        if (hasTrafficCamDevice(currentNode)) {
          bool enforcement = true;
          trafficcamSize += 1;
          String traffic = 'TRAFFIC_$trafficcamSize';
          speedCamDict[traffic] = [
            currentNode.latitudeStart,
            currentNode.longitudeStart,
            currentNode.latitudeEnd,
            currentNode.longitudeEnd,
            enforcement,
          ];
        }
      } else if ((hasRoleAttribute(currentNode) && hasSection(currentNode)) ||
          (hasEnforcementAttribute2(currentNode) &&
              hasEnforcementAverageSpeed(currentNode))) {
        bool enforcement = true;
        mobileCamSize += 1;
        String mobile = 'MOBILE_$mobileCamSize';
        speedCamDict[mobile] = [
          currentNode.latitudeStart,
          currentNode.longitudeStart,
          currentNode.latitudeEnd,
          currentNode.longitudeEnd,
          enforcement,
        ];
      }

      currentNode = currentNode.next;
    }

    return (fixedcamSize, trafficcamSize, mobileCamSize, speedCamDict);
  }

  bool hasRoadNameAttribute(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags.containsKey('name');
    }
  }

  bool hasExtendedRoadNameAttribute(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags.containsKey('addr:street');
    }
  }

  bool hasHouseNumberAttribute(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags.containsKey('addr:housenumber');
    }
  }

  String getRoadNameAttribute(Node node) {
    return node.tags['name'];
  }

  String getExtendedRoadNameAttribute(Node node) {
    return node.tags['addr:street'];
  }

  String getHouseNumberAttribute(Node node) {
    return node.tags['addr:housenumber'];
  }

  bool hasHighwayAttribute(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags.containsKey('highway');
    }
  }

  bool hasSpeedCamAttribute(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags.containsKey('speed_camera');
    }
  }

  bool hasCrossingAttribute(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags.containsKey('crossing');
    }
  }

  bool hasEnforcementAttribute(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags.containsKey('enforcement_camera');
    }
  }

  bool hasEnforcementAttribute2(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags.containsKey('enforcement');
    }
  }

  bool hasDeviceAttribute(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags.containsKey('device');
    }
  }

  bool hasRoleAttribute(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags.containsKey('role');
    }
  }

  bool hasExtendedSpeedCam(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags['role'] == 'device';
    }
  }

  bool hasSection(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags['role'] == 'section';
    }
  }

  bool hasSpeedCam(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags['highway'] == 'speed_camera';
    }
  }

  bool hasTrafficCam(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags['speed_camera'] == 'traffic_signals';
    }
  }

  bool hasTrafficCamCrossing(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags['crossing'] == 'traffic_signals';
    }
  }

  bool hasTrafficCamEnforcement(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags['enforcement'] == 'traffic_signals';
    }
  }

  bool hasEnforcementAverageSpeed(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags['enforcement'] == 'average_speed';
    }
  }

  bool hasTrafficCamDevice(Node? node) {
    if (node == null) {
      return false;
    } else {
      return node.tags['device'] == 'red_signal_camera';
    }
  }

  (double, double) getSpeedCamStartCoordinates(Node? node) {
    if (node == null) {
      return (0.0, 0.0);
    } else {
      return (node.latitudeEnd, node.longitudeEnd);
    }
  }

  (double, double) getSpeedCamEndCoordinates(Node? node) {
    if (node == null) {
      return (0.0, 0.0);
    } else {
      return (node.latitudeStart, node.longitudeStart);
    }
  }

  void remove(int nodeId) {
    Node? currentNode = head;

    while (currentNode != null) {
      if (currentNode.id == nodeId) {
        if (currentNode.prev != null) {
          currentNode.prev!.next = currentNode.next;
          currentNode.next?.prev = currentNode.prev;
        } else {
          head = currentNode.next;
          currentNode.next?.prev = null;
        }

        if (currentNode.next == null) {
          tail = currentNode.prev;
        }
        break;
      }
      currentNode = currentNode.next;
    }
  }
}

