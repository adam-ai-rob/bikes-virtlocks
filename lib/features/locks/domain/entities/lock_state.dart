import 'package:equatable/equatable.dart';

/// Represents the state of a virtual lock device
class LockState extends Equatable {
  /// Unique identifier for the thing/lock
  final String thingId;

  /// Whether the lock is connected to AWS IoT
  final bool connected;

  /// Lock state: 1 = locked, 0 = unlocked
  final int locked;

  /// Empty state: 1 = empty (no bike), 0 = occupied (bike present)
  final int empty;

  /// Clamp state: 1 = OK, 0 = error
  final int lockClamps;

  /// Timer in milliseconds until auto-lock, null if inactive
  final int? timer;

  /// Last update timestamp
  final DateTime? lastUpdate;

  const LockState({
    required this.thingId,
    this.connected = false,
    this.locked = 1,
    this.empty = 0,
    this.lockClamps = 1,
    this.timer,
    this.lastUpdate,
  });

  /// Create a copy with updated fields
  LockState copyWith({
    String? thingId,
    bool? connected,
    int? locked,
    int? empty,
    int? lockClamps,
    int? timer,
    DateTime? lastUpdate,
  }) {
    return LockState(
      thingId: thingId ?? this.thingId,
      connected: connected ?? this.connected,
      locked: locked ?? this.locked,
      empty: empty ?? this.empty,
      lockClamps: lockClamps ?? this.lockClamps,
      timer: timer ?? this.timer,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }

  /// Whether the lock is currently locked
  bool get isLocked => locked == 1;

  /// Whether the lock slot is empty (no bike)
  bool get isEmpty => empty == 1;

  /// Whether the clamps are in correct position
  bool get areClampsOk => lockClamps == 1;

  /// Whether there is an active timer
  bool get hasActiveTimer => timer != null && timer! > 0;

  /// Convert to shadow reported state format
  Map<String, dynamic> toShadowState() {
    return {
      'locked': locked,
      'empty': empty,
      'lock_clamps': lockClamps,
      'timer': timer,
    };
  }

  /// Convert to shadow reported state format for MQTT publishing
  Map<String, dynamic> toReportedState() {
    return {
      'locked': locked,
      'empty': empty,
      'lock_clamps': lockClamps,
      if (timer != null) 'timer': timer,
    };
  }

  /// Create from shadow state
  factory LockState.fromShadowState(
    String thingId,
    Map<String, dynamic> state, {
    bool connected = true,
  }) {
    return LockState(
      thingId: thingId,
      connected: connected,
      locked: state['locked'] as int? ?? 1,
      empty: state['empty'] as int? ?? 0,
      lockClamps: state['lock_clamps'] as int? ?? 1,
      timer: state['timer'] as int?,
      lastUpdate: DateTime.now(),
    );
  }

  /// Apply delta update from shadow
  LockState applyDelta(Map<String, dynamic> delta) {
    final state = delta['state'] as Map<String, dynamic>? ?? delta;

    return copyWith(
      locked: state['locked'] as int? ?? locked,
      empty: state['empty'] as int? ?? empty,
      lockClamps: state['lock_clamps'] as int? ?? lockClamps,
      timer: state['timer'] as int? ?? timer,
      lastUpdate: DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        thingId,
        connected,
        locked,
        empty,
        lockClamps,
        timer,
        lastUpdate,
      ];

  @override
  String toString() {
    return 'LockState(thingId: $thingId, connected: $connected, '
        'locked: $locked, empty: $empty, lockClamps: $lockClamps, '
        'timer: $timer)';
  }
}
