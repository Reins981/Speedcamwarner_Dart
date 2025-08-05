
/// Port of the ``MostProbableWay`` helper from the Python code base.  The
/// class keeps track of recently observed road names and determines the most
/// probable road based on repeated observations.  The implementation here is
/// intentionally lightweight; only the behaviour required by the tests has
/// been translated.
class MostProbableWay {
  String _mostProbableRoad = '<>';
  String _mostProbableSpeed = '';
  String _previousRoad = '<>';
  String _previousSpeed = '';
  dynamic _mostProbableTags;
  dynamic _previousTags;
  bool _firstLookup = true;
  bool nextMprListComplete = false;
  final List<String> _lastRoadnameList = [];
  final List<MapEntry<int, String>> _nextPossibleMprList = [];
  int maxRoadNames = 0;
  int maxPossibleMprCandidates = 0;
  int unstableCounter = 0;

  /// Max number of unstable updates before we accept a change.
  final int unstableLimit = 3;

  void increaseUnstableCounter() => unstableCounter++;
  int getUnstableCounter() => unstableCounter;
  void resetUnstableCounter() => unstableCounter = 0;

  void setMaximumNumberOfRoadNames(int maxnum) {
    maxRoadNames = maxnum;
  }

  void setMaximumNumberOfNextPossibleMprs(int maxnum) {
    maxPossibleMprCandidates = maxnum;
  }

  List<String> get lastRoadnameList => List.unmodifiable(_lastRoadnameList);
  List<MapEntry<int, String>> get nextPossibleMprList =>
      List.unmodifiable(_nextPossibleMprList);

  /// Add a candidate pair of (road class, road name) to the next possible list.
  /// Returns ``'MAX_REACHED'`` when the internal capacity has been hit.
  String addAttributesToNextPossibleMprList(int currentFr, String roadname) {
    if (_nextPossibleMprList.length >= maxPossibleMprCandidates) {
      return 'MAX_REACHED';
    }
    _nextPossibleMprList.add(MapEntry(currentFr, roadname));
    return 'MAX_NOT_REACHED';
  }

  void clearNextPossibleMprList() {
    _nextPossibleMprList.clear();
  }

  /// Maintain a sliding window of the most recent road names.  Once the maximum
  /// number of road names is reached the buffer is cleared before the new entry
  /// is appended, mirroring the Python behaviour.
  void addRoadnameToRoadnameList(String roadname) {
    if (_lastRoadnameList.length == maxRoadNames) {
      _lastRoadnameList.clear();
    }
    _lastRoadnameList.add(roadname);
  }

  /// Determine whether the candidates stored in [_nextPossibleMprList] point to
  /// a new most probable road.  The algorithm checks for consistency of the
  /// road class and name across the collected candidates and also handles the
  /// special case where the names indicate a crossroad (e.g. "A/B").
  bool isNextPossibleMprNewMpr({
    required int? currentFr,
    required int mostProbableRoadClass,
    required bool ramp,
    required bool nextMprListComplete,
  }) {
    if (currentFr == null) return false;

    if (0 <= mostProbableRoadClass && mostProbableRoadClass <= 1) {
      setMaximumNumberOfNextPossibleMprs(6);
    } else {
      setMaximumNumberOfNextPossibleMprs(4);
    }

    if ((currentFr >= 0 && currentFr <= 1) || ramp) {
      if (mostProbableRoadClass > 1) {
        // In the original implementation the rectangle thread might update
        // road candidates.  For the simplified port we simply allow the new
        // motorway class to take precedence.
        return true;
      }
      return true;
    }

    final roadClassEntries = _nextPossibleMprList.map((e) => e.key).toList();
    final roadNameEntries = _nextPossibleMprList.map((e) => e.value).toList();

    String? crossroad0;
    String? crossroad1;
    bool crossroadMpr = true;
    for (final roadName in roadNameEntries) {
      final parts = roadName.split('/');
      if (parts.length == 2) {
        crossroad0 = parts[0];
        crossroad1 = parts[1];
        break;
      }
    }

    if (crossroad0 != null && crossroad1 != null) {
      for (final name in roadNameEntries) {
        if (!name.contains(crossroad0)) {
          crossroadMpr = false;
          break;
        }
      }
      if (!crossroadMpr) {
        crossroadMpr = true;
        for (final name in roadNameEntries) {
          if (!name.contains(crossroad1)) {
            crossroadMpr = false;
            break;
          }
        }
      }
    } else {
      crossroadMpr = false;
    }

    final counts = <int, int>{};
    for (final rc in roadClassEntries) {
      counts[rc] = (counts[rc] ?? 0) + 1;
    }

    return nextMprListComplete &&
        (_nextPossibleMprList.toSet().length == 1 ||
            (counts[currentFr] ?? 0) == roadClassEntries.length ||
            crossroadMpr);
  }

  bool isFirstLookup() => _firstLookup;
  void setFirstLookup(bool lookup) => _firstLookup = lookup;

  void setMostProbableRoad(String roadname) => _mostProbableRoad = roadname;
  void setMostProbableSpeed(String speed) => _mostProbableSpeed = speed;
  void setPreviousRoad(String roadname) => _previousRoad = roadname;
  void setPreviousSpeed(String speed) => _previousSpeed = speed;
  void setMostProbableTags(dynamic tags) => _mostProbableTags = tags;
  void setPreviousTags(dynamic tags) => _previousTags = tags;

  String getMostProbableRoad() => _mostProbableRoad;
  String getMostProbableSpeed() => _mostProbableSpeed;
  dynamic getMostProbableTags() => _mostProbableTags;
  String getPreviousRoad() => _previousRoad;
  String getPreviousSpeed() => _previousSpeed;
  dynamic getPreviousTags() => _previousTags;
}
