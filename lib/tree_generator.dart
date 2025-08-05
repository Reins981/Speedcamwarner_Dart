import 'dart:collection';

class BinarySearchTree {
  TreeNode? root;
  TreeNode? way;
  int size = 0;

  int get length => size;

  void deleteTree() {
    root = null;
    way = null;
    size = 0;
  }

  TreeNode? operator [](int nodeId) => get(nodeId);

  bool contains(int nodeId) => _get(nodeId, root) != null;

  void insert(int nodeId, int wayId, Map<String, dynamic> tags) {
    if (root != null) {
      _insert(nodeId, wayId, tags, root!);
    } else {
      root = TreeNode(key: nodeId, wayId: wayId, tags: tags);
    }
    size += 1;
  }

  void _insert(int nodeId, int wayId, Map<String, dynamic> tags, TreeNode currentNode) {
    if (nodeId < currentNode.key) {
      if (currentNode.hasLeftChild()) {
        _insert(nodeId, wayId, tags, currentNode.leftChild!);
      } else {
        currentNode.leftChild =
            TreeNode(key: nodeId, wayId: wayId, tags: tags, parent: currentNode);
      }
    } else if (nodeId > currentNode.key) {
      if (currentNode.hasRightChild()) {
        _insert(nodeId, wayId, tags, currentNode.rightChild!);
      } else {
        currentNode.rightChild =
            TreeNode(key: nodeId, wayId: wayId, tags: tags, parent: currentNode);
      }
    } else {
      currentNode.combinedTags.add(tags);
      currentNode.additionalWayId.add(wayId);
    }
  }

  TreeNode? get(int nodeId) {
    if (root != null) {
      final res = _get(nodeId, root!);
      if (res != null) {
        way = res;
        return res;
      }
    }
    return null;
  }

  TreeNode? _get(int nodeId, TreeNode? currentNode) {
    if (currentNode == null) {
      return null;
    } else if (currentNode.key == nodeId) {
      way = currentNode;
      return currentNode;
    } else if (nodeId < currentNode.key) {
      return _get(nodeId, currentNode.leftChild);
    } else {
      return _get(nodeId, currentNode.rightChild);
    }
  }

  TreeNode? _getNextNode(int nodeId, TreeNode? currentNode) {
    if (currentNode == null) {
      return null;
    } else if (currentNode.key == nodeId) {
      way = currentNode.hasRightChild() ? currentNode.rightChild : null;
      return currentNode.rightChild;
    } else if (nodeId < currentNode.key) {
      return _get(nodeId, currentNode.leftChild);
    } else {
      return _get(nodeId, currentNode.rightChild);
    }
  }

  TreeNode? getNextNode(int nodeId) {
    if (root != null) {
      final res = _getNextNode(nodeId, root!);
      if (res != null) {
        way = res;
        return res;
      }
    }
    return null;
  }

  static bool hasCombinedTags(TreeNode way) {
    if (way.combinedTags.isEmpty) {
      return false;
    } else {
      print(' Combined tags found');
      return true;
    }
  }

  static bool hasHighwayAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('highway')) {
        print(' Highway attribute found');
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasHazardAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('hazard')) {
        print(' Hazard found');
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasWaterwayAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('waterway')) {
        print(' Waterway found');
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasAccessConditionalAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('access:conditional')) {
        print(' Access Conditional found');
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasBoundaryAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('boundary')) {
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasRoleAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('role')) {
        print(' Role attribute found');
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasSpeedcamAttribute(TreeNode way) {
    print(' Speedcam attribute found');
    return way.tags['role'] == 'device';
  }

  static bool hasSpeedCam(TreeNode way) {
    print(' Speedcam found');
    return way.tags['highway'] == 'speed_camera';
  }

  static bool hasSection(TreeNode way) {
    print(' Section attribute found');
    return way.tags['role'] == 'section';
  }

  static bool hasMaxspeedAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('maxspeed')) {
        print(' Maxspeed attribute found');
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasMaxspeedConditionalAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('maxspeed:conditional')) {
        print(' Maxspeed conditional attribute found');
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasMaxspeedLaneAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('maxspeed:lanes')) {
        print(' Maxspeed lanes attribute found');
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasRoadNameAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('name')) {
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasTunnelAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('tunnel')) {
        print(' Tunnel attribute found');
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasRefAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('ref')) {
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasExtendedRoadNameAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('addr:street')) {
        print(' Extended road name  attribute found');
        return true;
      } else {
        return false;
      }
    }
  }

  static bool hasAmenityAttribute(TreeNode? way) {
    if (way == null) {
      return false;
    } else {
      if (way.tags.containsKey('amenity')) {
        print(' Facility attribute found');
        return true;
      } else {
        return false;
      }
    }
  }

  static bool isFuelStation(TreeNode way) {
    return way.tags['amenity'] == 'fuel';
  }

  static bool isUrban(TreeNode way) {
    print(' Administrative area found');
    return way.tags['boundary'] == 'administrative';
  }

  static String getMaxspeedValue(TreeNode way) {
    print(' Maxspeed value is ${way.tags['maxspeed']}');
    return way.tags['maxspeed'].toString();
  }

  static String getMaxspeedConditionalValue(TreeNode way) {
    print(' ${way.tags['maxspeed:conditional']}');
    return way.tags['maxspeed:conditional'].toString();
  }

  static String getMaxspeedLaneValue(TreeNode way) {
    print(' ${way.tags['maxspeed:lanes']}');
    return way.tags['maxspeed:lanes'].toString();
  }

  static List<Map<String, dynamic>> getCombinedTags(TreeNode way) {
    return way.combinedTags;
  }

  static String getRoadNameValue(TreeNode way) {
    return way.tags['name'].toString();
  }

  static String getExtendedRoadNameValue(TreeNode way) {
    return way.tags['addr:street'].toString();
  }

  static String getRefValue(TreeNode way) {
    return way.tags['ref'].toString();
  }

  static String getHighwayValue(TreeNode way) {
    return way.tags['highway'].toString();
  }

  static String getHazardValue(TreeNode way) {
    return way.tags['hazard'].toString();
  }

  static String getWaterwayValue(TreeNode way) {
    return way.tags['waterway'].toString();
  }

  static String getBoundaryValue(TreeNode way) {
    return way.tags['boundary'].toString();
  }

  static String getAccessConditionalValue(TreeNode way) {
    return way.tags['access:conditional'].toString();
  }

  void delete(int nodeId) {
    if (size > 1) {
      final nodeToRemove = _get(nodeId, root);
      if (nodeToRemove != null) {
        remove(nodeToRemove);
        size -= 1;
      } else {
        throw ArgumentError('Error, key not in tree');
      }
    } else if (size == 1 && root?.key == nodeId) {
      root = null;
      size -= 1;
    } else {
      throw ArgumentError('Error, key not in tree');
    }
  }

  TreeNode findMin() {
    if (root == null) {
      throw StateError('Tree is empty');
    }
    return root!.findMin();
  }

  void remove(TreeNode currentNode) {
    if (currentNode.isLeaf()) {
      if (currentNode.isLeftChild()) {
        currentNode.parent!.leftChild = null;
      } else {
        currentNode.parent!.rightChild = null;
      }
    } else if (currentNode.hasBothChildren()) {
      final succ = currentNode.findSuccessor()!;
      succ.spliceOut();
      currentNode.key = succ.key;
      currentNode.payload = succ.payload;
    } else {
      if (currentNode.hasLeftChild()) {
        if (currentNode.isLeftChild()) {
          currentNode.leftChild!.parent = currentNode.parent;
          currentNode.parent!.leftChild = currentNode.leftChild;
        } else if (currentNode.isRightChild()) {
          currentNode.leftChild!.parent = currentNode.parent;
          currentNode.parent!.rightChild = currentNode.leftChild;
        } else {
          currentNode.replaceNodeData(
              currentNode.leftChild!.key,
              currentNode.leftChild!.payload,
              currentNode.leftChild!.leftChild,
              currentNode.leftChild!.rightChild);
        }
      } else {
        if (currentNode.isLeftChild()) {
          currentNode.rightChild!.parent = currentNode.parent;
          currentNode.parent!.leftChild = currentNode.rightChild;
        } else if (currentNode.isRightChild()) {
          currentNode.rightChild!.parent = currentNode.parent;
          currentNode.parent!.rightChild = currentNode.rightChild;
        } else {
          currentNode.replaceNodeData(
              currentNode.rightChild!.key,
              currentNode.rightChild!.payload,
              currentNode.rightChild!.leftChild,
              currentNode.rightChild!.rightChild);
        }
      }
    }
  }
}

class TreeNode {
  int key;
  int wayId;
  List<int> additionalWayId = [];
  Map<String, dynamic> tags;
  List<Map<String, dynamic>> combinedTags = [];
  TreeNode? leftChild;
  TreeNode? rightChild;
  TreeNode? parent;
  dynamic payload;

  TreeNode({
    required this.key,
    required this.wayId,
    Map<String, dynamic>? tags,
    this.leftChild,
    this.rightChild,
    this.parent,
  }) : tags = tags ?? {};

  bool hasLeftChild() => leftChild != null;
  bool hasRightChild() => rightChild != null;
  bool isLeftChild() => parent != null && parent!.leftChild == this;
  bool isRightChild() => parent != null && parent!.rightChild == this;
  bool isRoot() => parent == null;
  bool isLeaf() => leftChild == null && rightChild == null;
  bool hasAnyChildren() => leftChild != null || rightChild != null;
  bool hasBothChildren() => leftChild != null && rightChild != null;

  void replaceNodeData(int key, dynamic value, TreeNode? lc, TreeNode? rc) {
    this.key = key;
    payload = value;
    leftChild = lc;
    rightChild = rc;
    if (hasLeftChild()) {
      leftChild!.parent = this;
    }
    if (hasRightChild()) {
      rightChild!.parent = this;
    }
  }

  void spliceOut() {
    if (isLeaf()) {
      if (isLeftChild()) {
        parent!.leftChild = null;
      } else {
        parent!.rightChild = null;
      }
    } else if (hasAnyChildren()) {
      if (hasLeftChild()) {
        if (isLeftChild()) {
          parent!.leftChild = leftChild;
        } else {
          parent!.rightChild = leftChild;
        }
        leftChild!.parent = parent;
      } else {
        if (isLeftChild()) {
          parent!.leftChild = rightChild;
        } else {
          parent!.rightChild = rightChild;
        }
        rightChild!.parent = parent;
      }
    }
  }

  TreeNode findMin() {
    var current = this;
    while (current.hasLeftChild()) {
      current = current.leftChild!;
    }
    return current;
  }

  TreeNode? findSuccessor() {
    TreeNode? succ;
    if (hasRightChild()) {
      succ = rightChild!.findMin();
    } else {
      if (parent != null) {
        if (isLeftChild()) {
          succ = parent;
        } else {
          parent!.rightChild = null;
          succ = parent!.findSuccessor();
          parent!.rightChild = this;
        }
      }
    }
    return succ;
  }

  Iterable<TreeNode> inOrderTraversal() sync* {
    if (leftChild != null) yield* leftChild!.inOrderTraversal();
    yield this;
    if (rightChild != null) yield* rightChild!.inOrderTraversal();
  }
}

