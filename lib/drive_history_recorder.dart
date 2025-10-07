import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:workspace/gps_thread.dart';
import 'package:workspace/speed_cam_warner.dart';
import 'gps_producer.dart';
import 'overspeed_checker.dart';
import 'rectangle_calculator.dart';

/// Types of events captured during a driving session.
enum DriveEventKind {
  speedCamera,
  construction,
  overspeed,
  topSpeed,
  maxAcceleration
}

/// Immutable record describing a notable driving event such as passing a speed
/// camera, encountering roadworks or driving above the speed limit.
class DriveEvent {
  const DriveEvent({
    required this.id,
    required this.kind,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.subtitle,
    this.details = const <String, dynamic>{},
    this.endTimestamp,
    this.isOngoing = false,
    this.maxOverspeed,
    this.topSpeed,
    this.maxAcceleration,
  });

  final int id;
  final DriveEventKind kind;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final String title;
  final String? subtitle;
  final Map<String, dynamic> details;
  final DateTime? endTimestamp;
  final bool isOngoing;
  final int? maxOverspeed;
  final int? topSpeed;
  final double? maxAcceleration;

  /// Returns the duration between [timestamp] and [endTimestamp] (or now if the
  /// event is still ongoing).
  Duration? get duration {
    if (endTimestamp != null) {
      return endTimestamp!.difference(timestamp);
    }
    if (isOngoing) {
      return DateTime.now().difference(timestamp);
    }
    return null;
  }

  DriveEvent copyWith({
    double? latitude,
    double? longitude,
    String? title,
    String? subtitle,
    Map<String, dynamic>? details,
    DateTime? timestamp,
    DateTime? endTimestamp,
    bool? isOngoing,
    int? maxOverspeed,
    int? topSpeed,
    double? maxAcceleration,
  }) {
    return DriveEvent(
      id: id,
      kind: kind,
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      details: details ?? this.details,
      endTimestamp: endTimestamp ?? this.endTimestamp,
      isOngoing: isOngoing ?? this.isOngoing,
      maxOverspeed: maxOverspeed ?? this.maxOverspeed,
      topSpeed: topSpeed ?? this.topSpeed,
      maxAcceleration: maxAcceleration ?? this.maxAcceleration,
    );
  }
}

/// Aggregated session metrics derived from recorded events.
class DriveSessionSummary {
  const DriveSessionSummary({
    required this.speedCameraCount,
    required this.constructionCount,
    required this.overspeedCount,
    required this.overspeedDuration,
    required this.maxOverspeed,
    required this.topSpeed,
    required this.maxAcceleration,
  });

  factory DriveSessionSummary.empty() => const DriveSessionSummary(
        speedCameraCount: 0,
        constructionCount: 0,
        overspeedCount: 0,
        overspeedDuration: Duration.zero,
        maxOverspeed: 0,
        topSpeed: 0,
        maxAcceleration: 0.0,
      );

  final int speedCameraCount;
  final int constructionCount;
  final int overspeedCount;
  final Duration overspeedDuration;
  final int maxOverspeed;
  final int topSpeed;
  final double maxAcceleration;

  DriveSessionSummary copyWith({
    int? speedCameraCount,
    int? constructionCount,
    int? overspeedCount,
    Duration? overspeedDuration,
    int? maxOverspeed,
    int? topSpeed,
    double? maxAcceleration,
  }) {
    return DriveSessionSummary(
      speedCameraCount: speedCameraCount ?? this.speedCameraCount,
      constructionCount: constructionCount ?? this.constructionCount,
      overspeedCount: overspeedCount ?? this.overspeedCount,
      overspeedDuration: overspeedDuration ?? this.overspeedDuration,
      maxOverspeed: maxOverspeed ?? this.maxOverspeed,
      topSpeed: topSpeed ?? this.topSpeed,
      maxAcceleration: maxAcceleration ?? this.maxAcceleration,
    );
  }
}

/// Captures drive events by listening to calculator streams and the
/// [OverspeedChecker]. Consumers can present the accumulated events through a
/// [ValueListenable] or reset the recorder when a new session starts.
class DriveHistoryRecorder {
  DriveHistoryRecorder({
    required this.calculator,
    required this.speedCamWarner,
    required this.overspeedChecker,
    required this.gpsProducer,
    required this.gpsThread,
  }) {
    _subscriptions
        .add(speedCamWarner.passedCameras.listen((event) => _onCamera(event)));
    _subscriptions.add(
      calculator.constructions.listen((rect) {
        if (rect != null) {
          _onConstruction(rect);
        }
      }),
    );
    _subscriptions
        .add(gpsThread.topSpeedStream.listen((event) => _onTopSpeed(event)));
    _subscriptions.add(gpsProducer.maxAccelStream
        .listen((event) => _onMaxAcceleration(event)));
    overspeedChecker.difference.addListener(_onOverspeed);
  }

  final RectangleCalculatorThread calculator;
  final SpeedCamWarner speedCamWarner;
  final OverspeedChecker overspeedChecker;
  final GpsProducer gpsProducer;
  final GpsThread gpsThread;

  final ValueNotifier<List<DriveEvent>> events =
      ValueNotifier<List<DriveEvent>>(const <DriveEvent>[]);
  final ValueNotifier<DriveSessionSummary> summary =
      ValueNotifier<DriveSessionSummary>(DriveSessionSummary.empty());

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  DriveEvent? _activeOverspeed;
  Timer? _overspeedTicker;
  Duration _completedOverspeedDuration = Duration.zero;
  Duration _activeOverspeedDuration = Duration.zero;
  int _eventId = 0;

  /// Reset the recorder, clearing all events and metrics.
  void reset() {
    _completedOverspeedDuration = Duration.zero;
    _activeOverspeedDuration = Duration.zero;
    _activeOverspeed = null;
    _cancelTicker();
    events.value = const <DriveEvent>[];
    summary.value = DriveSessionSummary.empty();
  }

  /// Called when a driving session is about to start.
  void startSession() {
    reset();
  }

  /// Finalises ongoing events (if any) at the end of a session.
  void endSession() {
    _finaliseActiveOverspeed();
  }

  void _onCamera(SpeedCameraEvent event) {
    final String cameraLabel = event.name?.trim().isNotEmpty == true
        ? event.name!.trim()
        : 'Speed camera';
    final String? subtitle = event.maxspeed != null
        ? 'Limit ${event.maxspeed} km/h'
        : (event.direction != null ? 'Direction ${event.direction}' : null);
    final DriveEvent driveEvent = DriveEvent(
      id: _nextId(),
      kind: DriveEventKind.speedCamera,
      timestamp: DateTime.now(),
      latitude: event.latitude,
      longitude: event.longitude,
      title: cameraLabel,
      subtitle: subtitle,
      details: <String, dynamic>{
        'flags': <String>[
          if (event.fixed) 'Fixed',
          if (event.mobile) 'Mobile',
          if (event.traffic) 'Traffic',
          if (event.distance) 'Average speed',
          if (event.predictive) 'Predicted',
        ],
        if (event.maxspeed != null) 'limit': event.maxspeed,
      },
    );
    _addEvent(driveEvent);
    final DriveSessionSummary current = summary.value;
    summary.value = current.copyWith(
      speedCameraCount: current.speedCameraCount + 1,
    );
  }

  void _onTopSpeed(int event) {
    final DriveEvent driveEvent = DriveEvent(
      id: _nextId(),
      kind: DriveEventKind.topSpeed,
      timestamp: DateTime.now(),
      latitude: 0.0,
      longitude: 0.0,
      title: "TopSpeed",
      subtitle: "",
      topSpeed: event,
    );
    _addEvent(driveEvent);
    final DriveSessionSummary current = summary.value;
    summary.value = current.copyWith(
      topSpeed: math.max(current.topSpeed, event),
    );
  }

  void _onMaxAcceleration(double event) {
    final DriveEvent driveEvent = DriveEvent(
      id: _nextId(),
      kind: DriveEventKind.maxAcceleration,
      timestamp: DateTime.now(),
      latitude: 0.0,
      longitude: 0.0,
      title: "MaxAcceleration",
      subtitle: "",
      maxAcceleration: event,
    );
    _addEvent(driveEvent);
    final DriveSessionSummary current = summary.value;
    summary.value = current.copyWith(
      maxAcceleration: math.max(current.maxAcceleration, event),
    );
  }

  void _onConstruction(GeoRect rect) async {
    final double latitude = rect.minLat;
    final double longitude = rect.minLon;
    final DriveEvent driveEvent = DriveEvent(
      id: _nextId(),
      kind: DriveEventKind.construction,
      timestamp: DateTime.now(),
      latitude: latitude,
      longitude: longitude,
      title: 'Road work detected',
      subtitle:
          'Zone ${await RectangleCalculatorThread.getRoadNearestRoadName(latitude, longitude) ?? "Unknown"}',
      details: <String, dynamic>{
        'bounds': rect,
      },
    );
    _addEvent(driveEvent);
    final DriveSessionSummary current = summary.value;
    summary.value = current.copyWith(
      constructionCount: current.constructionCount + 1,
    );
  }

  void _onOverspeed() {
    final int? diff = overspeedChecker.difference.value;
    if (diff != null && diff > 0) {
      final List<double> coords = gpsProducer.get_lon_lat();
      final double longitude = coords[0];
      final double latitude = coords[1];
      if (_activeOverspeed == null) {
        final DriveEvent newEvent = DriveEvent(
          id: _nextId(),
          kind: DriveEventKind.overspeed,
          timestamp: DateTime.now(),
          latitude: latitude,
          longitude: longitude,
          title: '+$diff km/h over limit',
          subtitle: 'Ease off to return within the limit',
          details: <String, dynamic>{'peak': diff},
          isOngoing: true,
          maxOverspeed: diff,
        );
        _activeOverspeed = newEvent;
        _addEvent(newEvent);
        _activeOverspeedDuration = Duration.zero;
        final DriveSessionSummary current = summary.value;
        summary.value = current.copyWith(
          overspeedCount: current.overspeedCount + 1,
          maxOverspeed: math.max(current.maxOverspeed, diff),
          overspeedDuration:
              _completedOverspeedDuration + _activeOverspeedDuration,
        );
        _startTicker();
      } else {
        final DriveEvent updated = _activeOverspeed!.copyWith(
          latitude: latitude,
          longitude: longitude,
          title: '+$diff km/h over limit',
          details: <String, dynamic>{
            ..._activeOverspeed!.details,
            'peak': math.max(_activeOverspeed!.maxOverspeed ?? diff, diff),
          },
          maxOverspeed: math.max(_activeOverspeed!.maxOverspeed ?? diff, diff),
        );
        _activeOverspeed = updated;
        _replaceEvent(updated);
        final DriveSessionSummary current = summary.value;
        summary.value = current.copyWith(
          maxOverspeed: math.max(current.maxOverspeed, diff),
        );
      }
      _refreshActiveOverspeed();
    } else {
      _finaliseActiveOverspeed();
    }
  }

  void _refreshActiveOverspeed() {
    if (_activeOverspeed == null) return;
    final DateTime now = DateTime.now();
    _activeOverspeedDuration = now.difference(_activeOverspeed!.timestamp);
    final DriveEvent updated =
        _activeOverspeed!.copyWith(endTimestamp: now, isOngoing: true);
    _activeOverspeed = updated;
    _replaceEvent(updated);
    summary.value = summary.value.copyWith(
      overspeedDuration: _completedOverspeedDuration + _activeOverspeedDuration,
    );
  }

  void _finaliseActiveOverspeed() {
    if (_activeOverspeed == null) return;
    _cancelTicker();
    final DateTime now = DateTime.now();
    final DriveEvent completed =
        _activeOverspeed!.copyWith(endTimestamp: now, isOngoing: false);
    _activeOverspeed = completed;
    _replaceEvent(completed);
    final Duration duration = completed.duration ?? _activeOverspeedDuration;
    _completedOverspeedDuration += duration;
    _activeOverspeedDuration = Duration.zero;
    summary.value = summary.value.copyWith(
      overspeedDuration: _completedOverspeedDuration,
      maxOverspeed:
          math.max(summary.value.maxOverspeed, completed.maxOverspeed ?? 0),
    );
    _activeOverspeed = null;
  }

  void _addEvent(DriveEvent event) {
    final List<DriveEvent> updated = List<DriveEvent>.from(events.value)
      ..add(event);
    events.value = updated;
  }

  void _replaceEvent(DriveEvent event) {
    final List<DriveEvent> updated = List<DriveEvent>.from(events.value);
    final int index = updated.indexWhere((DriveEvent e) => e.id == event.id);
    if (index >= 0) {
      updated[index] = event;
      events.value = updated;
    }
  }

  int _nextId() => ++_eventId;

  void _startTicker() {
    _overspeedTicker ??= Timer.periodic(
        const Duration(seconds: 1), (_) => _refreshActiveOverspeed());
  }

  void _cancelTicker() {
    _overspeedTicker?.cancel();
    _overspeedTicker = null;
  }

  /// Dispose subscriptions and listeners.
  Future<void> dispose() async {
    _cancelTicker();
    overspeedChecker.difference.removeListener(_onOverspeed);
    for (final StreamSubscription<dynamic> sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }
}
