import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../services/connection_manager.dart';
import '../../../services/storage_service.dart';
import '../../aws_config/providers/aws_config_providers.dart';
import '../domain/entities/lock_state.dart';

// Re-export for use in UI
export '../../../services/connection_manager.dart'
    show SimulationMode, RackGroup, ConnectionState;

/// Filter for virtual locks
enum LockFilter { all, connected, disconnected }

/// State for the virtual locks manager
class LocksState {
  final Map<String, LockState> locks;
  final LockFilter filter;
  final Set<String> selectedLocks;
  final bool isConnecting;
  final bool isConnected;
  final String? error;
  final SimulationMode simulationMode;
  final Map<String, RackGroup> rackGroups;

  const LocksState({
    this.locks = const {},
    this.filter = LockFilter.all,
    this.selectedLocks = const {},
    this.isConnecting = false,
    this.isConnected = false,
    this.error,
    this.simulationMode = SimulationMode.masterRack,
    this.rackGroups = const {},
  });

  /// Get filtered locks list
  List<LockState> get filteredLocks {
    var locksList = locks.values.toList();

    switch (filter) {
      case LockFilter.connected:
        locksList = locksList.where((l) => l.connected).toList();
        break;
      case LockFilter.disconnected:
        locksList = locksList.where((l) => !l.connected).toList();
        break;
      case LockFilter.all:
        break;
    }

    // Sort by thingId
    locksList.sort((a, b) => a.thingId.compareTo(b.thingId));
    return locksList;
  }

  /// Get count of connected locks
  int get connectedCount => locks.values.where((l) => l.connected).length;

  /// Get count of disconnected locks
  int get disconnectedCount => locks.values.where((l) => !l.connected).length;

  /// Get selected lock states
  List<LockState> get selectedLockStates =>
      selectedLocks.map((id) => locks[id]).whereType<LockState>().toList();

  /// Get connection info description
  String get connectionInfo {
    final connMgr = ConnectionManager.instance;
    final connections = connMgr.connections;
    if (connections.isEmpty) return 'No connections';

    final connected = connections.values.where((c) => c.isConnected).length;
    return '$connected connection(s) active';
  }

  LocksState copyWith({
    Map<String, LockState>? locks,
    LockFilter? filter,
    Set<String>? selectedLocks,
    bool? isConnecting,
    bool? isConnected,
    String? error,
    bool clearError = false,
    SimulationMode? simulationMode,
    Map<String, RackGroup>? rackGroups,
  }) {
    return LocksState(
      locks: locks ?? this.locks,
      filter: filter ?? this.filter,
      selectedLocks: selectedLocks ?? this.selectedLocks,
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      error: clearError ? null : error,
      simulationMode: simulationMode ?? this.simulationMode,
      rackGroups: rackGroups ?? this.rackGroups,
    );
  }
}

/// Notifier for managing virtual locks state
class LocksNotifier extends StateNotifier<LocksState> {
  final Ref _ref;
  Timer? _timerUpdateTimer;
  Timer? _heartbeatTimer;
  StreamSubscription<ConnectionState>? _connectionSubscription;
  StreamSubscription<(String, Map<String, dynamic>)>? _shadowDeltaSubscription;

  LocksNotifier(this._ref) : super(const LocksState()) {
    // Start timer update loop for countdown display
    _startTimerUpdates();
    // Start heartbeat loop for periodic state reporting
    _startHeartbeat();
    // Listen to connection state changes
    _setupConnectionListeners();
  }

  @override
  void dispose() {
    _timerUpdateTimer?.cancel();
    _heartbeatTimer?.cancel();
    _connectionSubscription?.cancel();
    _shadowDeltaSubscription?.cancel();
    super.dispose();
  }

  void _setupConnectionListeners() {
    final connMgr = ConnectionManager.instance;

    // Listen to global connection state changes
    _connectionSubscription = connMgr.globalStateStream.listen((connState) {
      final isConnected = connState == ConnectionState.connected;
      final isConnecting = connState == ConnectionState.connecting;

      state = state.copyWith(
        isConnected: isConnected,
        isConnecting: isConnecting,
      );

      // Update individual lock connection status based on their managed state
      _updateLockConnectionStates();
    });

    // Listen to shadow delta messages
    _shadowDeltaSubscription = connMgr.shadowDeltaStream.listen((message) {
      final (thingId, delta) = message;
      _handleShadowDelta(thingId, delta);
    });
  }

  void _updateLockConnectionStates() {
    final connMgr = ConnectionManager.instance;
    final locks = Map<String, LockState>.from(state.locks);
    bool hasChanges = false;

    for (final thingId in locks.keys) {
      final isConnected = connMgr.isThingConnected(thingId);
      if (locks[thingId]!.connected != isConnected) {
        locks[thingId] = locks[thingId]!.copyWith(connected: isConnected);
        hasChanges = true;
      }
    }

    if (hasChanges) {
      state = state.copyWith(locks: locks);
    }
  }

  void _handleShadowDelta(String thingId, Map<String, dynamic> delta) {
    final lock = state.locks[thingId];
    if (lock == null) {
      AppLogger.debug('Received delta for unknown lock: $thingId');
      return;
    }

    // Extract state from delta
    final desiredState = delta['state'] as Map<String, dynamic>?;
    if (desiredState == null) return;

    AppLogger.info('Received shadow delta for $thingId: $desiredState');

    // Apply delta to lock state
    final updatedLock = lock.applyDelta(desiredState);
    final locks = Map<String, LockState>.from(state.locks);
    locks[thingId] = updatedLock;
    state = state.copyWith(locks: locks);

    // Publish reported state back
    _publishReportedState(thingId, updatedLock);
  }

  Future<void> _publishReportedState(String thingId, LockState lock) async {
    final connMgr = ConnectionManager.instance;
    if (!connMgr.isThingConnected(thingId)) return;

    await connMgr.publishShadowUpdate(thingId, lock.toReportedState());
  }

  void _startTimerUpdates() {
    _timerUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimers();
    });
  }

  void _updateTimers() {
    bool hasChanges = false;
    final locks = Map<String, LockState>.from(state.locks);

    for (final thingId in locks.keys.toList()) {
      final lock = locks[thingId]!;
      if (lock.hasActiveTimer) {
        final newTimer = (lock.timer! - 1000).clamp(0, lock.timer!);
        if (newTimer != lock.timer) {
          var updatedLock = lock.copyWith(timer: newTimer);
          hasChanges = true;

          // Auto-lock when timer reaches 0
          if (newTimer == 0) {
            updatedLock = updatedLock.copyWith(locked: 1, timer: 0);
            AppLogger.info('Lock ${lock.thingId} auto-locked (timer expired)');
            // Publish auto-lock state
            if (lock.connected) {
              _publishReportedState(thingId, updatedLock);
            }
          }
          locks[thingId] = updatedLock;
        }
      }
    }

    if (hasChanges) {
      state = state.copyWith(locks: locks);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _publishHeartbeat();
    });
  }

  void _publishHeartbeat() {
    // Publish current state for all connected locks
    for (final entry in state.locks.entries) {
      final thingId = entry.key;
      final lock = entry.value;

      if (lock.connected) {
        AppLogger.debug('Heartbeat: publishing state for $thingId');
        _publishReportedState(thingId, lock);
      }
    }
  }

  /// Set simulation mode
  void setSimulationMode(SimulationMode mode) {
    ConnectionManager.instance.setMode(mode);
    state = state.copyWith(simulationMode: mode);
    AppLogger.info('Simulation mode changed to: ${mode.name}');
  }

  /// Load locks from things that have local certificates
  Future<void> loadLocks() async {
    state = state.copyWith(isConnecting: true, clearError: true);

    try {
      // Get things with local certificates
      final localThings = await StorageService.instance.listLocalThings();

      // Group things by rack
      final rackGroups = ConnectionManager.groupThingsByRack(localThings);
      AppLogger.info('Found ${rackGroups.length} racks from ${localThings.length} things');

      // Filter to only lock things (not masters) for display
      final lockThings = localThings.where((name) {
        return ConnectionManager.isLockDevice(name);
      }).toList();

      // Create lock states for each thing
      final locks = <String, LockState>{};
      for (final thingId in lockThings) {
        // Load saved state if exists, otherwise create default
        final config = await StorageService.instance.loadThingConfig(thingId);
        final savedState = config?['lastState'] as Map<String, dynamic>?;

        if (savedState != null) {
          locks[thingId] = LockState.fromShadowState(
            thingId,
            savedState,
            connected: false,
          );
        } else {
          locks[thingId] = LockState(thingId: thingId);
        }
      }

      state = state.copyWith(
        locks: locks,
        rackGroups: rackGroups,
        isConnecting: false,
      );

      // Sync connection states with any active connections
      _updateLockConnectionStates();

      AppLogger.info('Loaded ${locks.length} virtual locks in ${rackGroups.length} racks');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load locks', e, stackTrace);
      state = state.copyWith(
        isConnecting: false,
        error: e.toString(),
      );
    }
  }

  /// Connect to AWS IoT using the current simulation mode
  Future<bool> connect() async {
    if (state.isConnected || state.isConnecting) {
      return state.isConnected;
    }

    state = state.copyWith(isConnecting: true, clearError: true);

    try {
      // Get AWS config
      final awsConfig = _ref.read(awsConfigProvider);
      if (!awsConfig.hasActiveProfile) {
        throw Exception('No active AWS profile configured');
      }

      final endpoint = awsConfig.iotEndpoint;
      if (endpoint == null || endpoint.isEmpty) {
        throw Exception(
            'IoT endpoint not configured. Please discover endpoint in AWS Config.');
      }

      if (state.locks.isEmpty) {
        throw Exception('No locks available to connect');
      }

      final storage = StorageService.instance;

      // Check CA certificate exists
      if (!await storage.caCertExists()) {
        throw Exception('CA certificate not found. Please download it from AWS.');
      }

      // Get all thing names (locks + masters)
      final allThings = await storage.listLocalThings();

      AppLogger.warning('=== Connection Debug ===');
      AppLogger.warning('Mode: ${state.simulationMode.name}');
      AppLogger.warning('Endpoint: $endpoint');
      AppLogger.warning('Things: ${allThings.length}');
      AppLogger.warning('Locks: ${state.locks.length}');

      final connMgr = ConnectionManager.instance;

      // Connect based on simulation mode
      final success = await connMgr.connectAll(
        thingNames: allThings,
        endpoint: endpoint,
        getCertPath: (thingId) => storage.getThingCertPath(thingId) ?? '',
        getKeyPath: (thingId) => storage.getThingKeyPath(thingId) ?? '',
        caPath: storage.caCertPath,
      );

      if (!success && !connMgr.hasActiveConnections) {
        throw Exception('Failed to establish any connections to AWS IoT');
      }

      // Update connection states
      _updateLockConnectionStates();

      // Request current shadow state for all connected locks
      for (final thingId in state.locks.keys) {
        if (connMgr.isThingConnected(thingId)) {
          await connMgr.getShadow(thingId);
        }
      }

      AppLogger.info(
          'Connected with ${connMgr.connections.length} connection(s), '
          '${state.connectedCount} locks connected');

      return connMgr.hasActiveConnections;
    } catch (e, stackTrace) {
      final errorMsg = 'Failed to connect to AWS IoT: $e';
      AppLogger.error(errorMsg, e, stackTrace);
      state = state.copyWith(
        isConnecting: false,
        isConnected: false,
        error: errorMsg,
      );
      return false;
    }
  }

  /// Disconnect from AWS IoT
  void disconnect() {
    final connMgr = ConnectionManager.instance;
    connMgr.disconnectAll();

    // Update all locks to disconnected
    final locks = state.locks.map(
        (key, value) => MapEntry(key, value.copyWith(connected: false)));
    state = state.copyWith(
      locks: locks,
      isConnected: false,
      isConnecting: false,
    );

    AppLogger.info('Disconnected from AWS IoT');
  }

  /// Add a lock for a thing
  void addLock(String thingId) {
    if (state.locks.containsKey(thingId)) return;

    final locks = Map<String, LockState>.from(state.locks);
    locks[thingId] = LockState(thingId: thingId);
    state = state.copyWith(locks: locks);
  }

  /// Remove a lock
  void removeLock(String thingId) {
    if (!state.locks.containsKey(thingId)) return;

    final locks = Map<String, LockState>.from(state.locks);
    locks.remove(thingId);

    final selected = Set<String>.from(state.selectedLocks);
    selected.remove(thingId);

    state = state.copyWith(locks: locks, selectedLocks: selected);
  }

  /// Update lock state from shadow delta
  void updateLockState(String thingId, Map<String, dynamic> delta) {
    final lock = state.locks[thingId];
    if (lock == null) return;

    final updatedLock = lock.applyDelta(delta);
    final locks = Map<String, LockState>.from(state.locks);
    locks[thingId] = updatedLock;

    state = state.copyWith(locks: locks);
    AppLogger.debug('Updated lock state: $thingId');
  }

  /// Set lock connection status
  void setLockConnected(String thingId, bool connected) {
    final lock = state.locks[thingId];
    if (lock == null) return;

    final locks = Map<String, LockState>.from(state.locks);
    locks[thingId] = lock.copyWith(connected: connected);

    state = state.copyWith(locks: locks);
  }

  /// Toggle empty state (simulate bike taken/returned)
  /// Only allowed when lock is unlocked (simulates physical action)
  Future<void> toggleEmpty(String thingId) async {
    final lock = state.locks[thingId];
    if (lock == null) return;

    // Can only take/return bike when lock is unlocked
    if (lock.isLocked) {
      AppLogger.warning('Cannot toggle empty state while lock is locked: $thingId');
      return;
    }

    final newEmpty = lock.isEmpty ? 0 : 1;
    final locks = Map<String, LockState>.from(state.locks);
    final updatedLock = lock.copyWith(
      empty: newEmpty,
      lastUpdate: DateTime.now(),
    );
    locks[thingId] = updatedLock;

    state = state.copyWith(locks: locks);
    AppLogger.info('Toggled empty state for $thingId: $newEmpty');

    // Publish if connected
    if (lock.connected) {
      await _publishReportedState(thingId, updatedLock);
    }

    // Save state locally
    await _saveLocalState(thingId, updatedLock);
  }

  /// Toggle clamps state
  Future<void> toggleClamps(String thingId) async {
    final lock = state.locks[thingId];
    if (lock == null) return;

    final newClamps = lock.areClampsOk ? 0 : 1;
    final locks = Map<String, LockState>.from(state.locks);
    final updatedLock = lock.copyWith(
      lockClamps: newClamps,
      lastUpdate: DateTime.now(),
    );
    locks[thingId] = updatedLock;

    state = state.copyWith(locks: locks);
    AppLogger.info('Toggled clamps state for $thingId: $newClamps');

    // Publish if connected
    if (lock.connected) {
      await _publishReportedState(thingId, updatedLock);
    }

    // Save state locally
    await _saveLocalState(thingId, updatedLock);
  }

  /// Manually set locked state (usually controlled by shadow)
  Future<void> setLocked(String thingId, bool locked) async {
    final lock = state.locks[thingId];
    if (lock == null) return;

    final locks = Map<String, LockState>.from(state.locks);
    final updatedLock = lock.copyWith(
      locked: locked ? 1 : 0,
      timer: locked ? 0 : null, // Clear timer when locking
      lastUpdate: DateTime.now(),
    );
    locks[thingId] = updatedLock;

    state = state.copyWith(locks: locks);
    AppLogger.info('Set locked state for $thingId: $locked');

    // Publish if connected
    if (lock.connected) {
      await _publishReportedState(thingId, updatedLock);
    }

    // Save state locally
    await _saveLocalState(thingId, updatedLock);
  }

  /// Save lock state locally for persistence
  Future<void> _saveLocalState(String thingId, LockState lock) async {
    try {
      final config =
          await StorageService.instance.loadThingConfig(thingId) ?? {};
      config['lastState'] = lock.toReportedState();
      await StorageService.instance.saveThingConfig(thingId, config);
    } catch (e) {
      AppLogger.error('Failed to save local state for $thingId', e);
    }
  }

  /// Set filter
  void setFilter(LockFilter filter) {
    state = state.copyWith(filter: filter);
  }

  /// Toggle lock selection
  void toggleSelection(String thingId) {
    final selected = Set<String>.from(state.selectedLocks);
    if (selected.contains(thingId)) {
      selected.remove(thingId);
    } else {
      selected.add(thingId);
    }
    state = state.copyWith(selectedLocks: selected);
  }

  /// Select all visible locks
  void selectAll() {
    final selected = state.filteredLocks.map((l) => l.thingId).toSet();
    state = state.copyWith(selectedLocks: selected);
  }

  /// Clear selection
  void clearSelection() {
    state = state.copyWith(selectedLocks: {});
  }

  /// Bulk toggle empty state for selected locks
  Future<void> bulkToggleEmpty() async {
    for (final thingId in state.selectedLocks) {
      await toggleEmpty(thingId);
    }
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Set global connection status
  void setConnected(bool connected) {
    state = state.copyWith(isConnected: connected);

    // Update all locks connection status
    if (!connected) {
      final locks = state.locks
          .map((key, value) => MapEntry(key, value.copyWith(connected: false)));
      state = state.copyWith(locks: locks);
    }
  }
}

/// Provider for locks management
final locksProvider = StateNotifierProvider<LocksNotifier, LocksState>((ref) {
  return LocksNotifier(ref);
});

/// Provider for filtered locks
final filteredLocksProvider = Provider<List<LockState>>((ref) {
  return ref.watch(locksProvider).filteredLocks;
});

/// Provider for current filter
final locksFilterProvider = Provider<LockFilter>((ref) {
  return ref.watch(locksProvider).filter;
});

/// Provider for lock connection status
final locksConnectedProvider = Provider<bool>((ref) {
  return ref.watch(locksProvider).isConnected;
});

/// Provider for selected locks count
final selectedLocksCountProvider = Provider<int>((ref) {
  return ref.watch(locksProvider).selectedLocks.length;
});

/// Provider for current simulation mode
final simulationModeProvider = Provider<SimulationMode>((ref) {
  return ref.watch(locksProvider).simulationMode;
});

/// Provider for rack groups
final rackGroupsProvider = Provider<Map<String, RackGroup>>((ref) {
  return ref.watch(locksProvider).rackGroups;
});
