import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/constants/aws_constants.dart';
import '../core/utils/logger.dart';

/// Connection mode for virtual locks simulation
enum SimulationMode {
  /// Master device connects and manages all locks in the rack
  masterRack,

  /// Each lock connects independently
  individualLock,
}

/// Connection state for our connection manager
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

/// Represents a rack with its devices
class RackGroup {
  final String env;
  final String rackName;
  final String? masterThingId;
  final List<String> lockThingIds;

  RackGroup({
    required this.env,
    required this.rackName,
    this.masterThingId,
    required this.lockThingIds,
  });

  bool get hasMaster => masterThingId != null;

  String get fullRackName => '$env-$rackName';

  @override
  String toString() =>
      'RackGroup($fullRackName, master: $masterThingId, locks: ${lockThingIds.length})';
}

/// Represents a single MQTT connection with its managed things
class MqttConnection {
  final String connectionId;
  final String thingId; // The thing whose credentials are used
  final Set<String> managedThingIds; // Things managed by this connection
  MqttServerClient? client;
  ConnectionState connectionState = ConnectionState.disconnected;

  MqttConnection({
    required this.connectionId,
    required this.thingId,
    Set<String>? managedThingIds,
  }) : managedThingIds = managedThingIds ?? {thingId};

  bool get isConnected => connectionState == ConnectionState.connected;
}

/// Callback type for shadow delta messages
typedef ShadowDeltaCallback = void Function(
  String thingId,
  Map<String, dynamic> delta,
);

/// Manager for multiple MQTT connections
class ConnectionManager {
  ConnectionManager._();

  static final ConnectionManager instance = ConnectionManager._();

  final Map<String, MqttConnection> _connections = {};
  SimulationMode _mode = SimulationMode.masterRack;

  final _connectionStateController =
      StreamController<(String, ConnectionState)>.broadcast();
  final _shadowDeltaController =
      StreamController<(String, Map<String, dynamic>)>.broadcast();
  final _globalStateController =
      StreamController<ConnectionState>.broadcast();

  /// Stream of connection state changes (connectionId, state)
  Stream<(String, ConnectionState)> get connectionStateStream =>
      _connectionStateController.stream;

  /// Stream of shadow delta messages (thingId, delta)
  Stream<(String, Map<String, dynamic>)> get shadowDeltaStream =>
      _shadowDeltaController.stream;

  /// Stream of overall connection state
  Stream<ConnectionState> get globalStateStream =>
      _globalStateController.stream;

  /// Current simulation mode
  SimulationMode get mode => _mode;

  /// Set simulation mode
  void setMode(SimulationMode mode) {
    _mode = mode;
    AppLogger.info('Simulation mode set to: ${mode.name}');
  }

  /// Check if any connection is active
  bool get hasActiveConnections =>
      _connections.values.any((c) => c.isConnected);

  /// Get all connections
  Map<String, MqttConnection> get connections => Map.unmodifiable(_connections);

  /// Parse thing name to extract rack info
  /// Pattern: {env}-{rackName}-{deviceType}
  /// Examples: dev-RACK01-LOCK01, dev-RACK01-MASTER
  static (String env, String rackName, String deviceType)?
      parseThingName(String thingName) {
    final parts = thingName.split('-');
    if (parts.length < 3) return null;

    final env = parts[0];
    final rackName = parts[1];
    // Device type is everything after env-rackName-
    final deviceType = parts.sublist(2).join('-');

    return (env, rackName, deviceType);
  }

  /// Check if a thing is a master device
  static bool isMasterDevice(String thingName) {
    final parsed = parseThingName(thingName);
    if (parsed == null) return false;
    return parsed.$3.toUpperCase() == 'MASTER';
  }

  /// Check if a thing is a lock device
  static bool isLockDevice(String thingName) {
    final parsed = parseThingName(thingName);
    if (parsed != null) {
      // Standard naming: check device type part
      final deviceType = parsed.$3.toUpperCase();
      return deviceType.startsWith('LOCK') ||
          deviceType.contains('BIKE') ||
          deviceType.contains('SCOOTER');
    }
    // Non-standard naming: check the full thing name for keywords
    final upperName = thingName.toUpperCase();
    return upperName.contains('LOCK') ||
        upperName.contains('BIKE') ||
        upperName.contains('SCOOTER');
  }

  /// Group things by rack
  static Map<String, RackGroup> groupThingsByRack(List<String> thingNames) {
    final groups = <String, RackGroup>{};

    for (final thingName in thingNames) {
      final parsed = parseThingName(thingName);
      if (parsed == null) {
        AppLogger.warning('Could not parse thing name: $thingName');
        continue;
      }

      final (env, rackName, _) = parsed;
      final fullRackName = '$env-$rackName';

      if (!groups.containsKey(fullRackName)) {
        groups[fullRackName] = RackGroup(
          env: env,
          rackName: rackName,
          lockThingIds: [],
        );
      }

      final group = groups[fullRackName]!;

      if (isMasterDevice(thingName)) {
        groups[fullRackName] = RackGroup(
          env: group.env,
          rackName: group.rackName,
          masterThingId: thingName,
          lockThingIds: group.lockThingIds,
        );
      } else if (isLockDevice(thingName)) {
        group.lockThingIds.add(thingName);
      }
    }

    return groups;
  }

  /// Connect based on the current simulation mode
  Future<bool> connectAll({
    required List<String> thingNames,
    required String endpoint,
    required String Function(String thingId) getCertPath,
    required String Function(String thingId) getKeyPath,
    required String caPath,
  }) async {
    // Group things by rack
    final rackGroups = groupThingsByRack(thingNames);

    AppLogger.info(
        'Found ${rackGroups.length} racks with mode: ${_mode.name}');
    for (final group in rackGroups.values) {
      AppLogger.debug('  $group');
    }

    bool allSuccess = true;

    if (_mode == SimulationMode.masterRack) {
      // Connect using master for each rack, or first lock if no master
      for (final group in rackGroups.values) {
        final connectingThingId =
            group.masterThingId ?? group.lockThingIds.firstOrNull;
        if (connectingThingId == null) {
          AppLogger.warning('Rack ${group.fullRackName} has no devices');
          continue;
        }

        // Get managed things: master manages all locks in the rack
        final managedThings = <String>{};
        if (group.masterThingId != null) {
          managedThings.add(group.masterThingId!);
        }
        managedThings.addAll(group.lockThingIds);

        final certPath = getCertPath(connectingThingId);
        final keyPath = getKeyPath(connectingThingId);

        if (certPath.isEmpty || keyPath.isEmpty) {
          AppLogger.warning(
              'Missing certificates for $connectingThingId, skipping rack');
          continue;
        }

        final success = await _connectSingle(
          connectionId: group.fullRackName,
          thingId: connectingThingId,
          managedThingIds: managedThings,
          endpoint: endpoint,
          certPath: certPath,
          keyPath: keyPath,
          caPath: caPath,
        );

        if (!success) allSuccess = false;
      }
    } else {
      // Individual lock mode - connect each lock separately
      for (final thingName in thingNames) {
        if (!isLockDevice(thingName)) continue;

        final certPath = getCertPath(thingName);
        final keyPath = getKeyPath(thingName);

        if (certPath.isEmpty || keyPath.isEmpty) {
          AppLogger.warning('Missing certificates for $thingName, skipping');
          continue;
        }

        final success = await _connectSingle(
          connectionId: thingName,
          thingId: thingName,
          managedThingIds: {thingName},
          endpoint: endpoint,
          certPath: certPath,
          keyPath: keyPath,
          caPath: caPath,
        );

        if (!success) allSuccess = false;
      }
    }

    _updateGlobalState();
    return allSuccess;
  }

  /// Connect a single MQTT client
  Future<bool> _connectSingle({
    required String connectionId,
    required String thingId,
    required Set<String> managedThingIds,
    required String endpoint,
    required String certPath,
    required String keyPath,
    required String caPath,
  }) async {
    // Check if already connected
    if (_connections.containsKey(connectionId) &&
        _connections[connectionId]!.isConnected) {
      AppLogger.warning('Connection $connectionId already exists');
      return true;
    }

    final connection = MqttConnection(
      connectionId: connectionId,
      thingId: thingId,
      managedThingIds: managedThingIds,
    );

    _connections[connectionId] = connection;
    _updateConnectionState(connectionId, ConnectionState.connecting);

    try {
      // Verify certificate files exist
      final certFile = File(certPath);
      final keyFile = File(keyPath);
      final caFile = File(caPath);

      if (!await certFile.exists()) {
        throw Exception('Certificate file not found: $certPath');
      }
      if (!await keyFile.exists()) {
        throw Exception('Private key file not found: $keyPath');
      }
      if (!await caFile.exists()) {
        throw Exception('CA certificate file not found: $caPath');
      }

      AppLogger.debug('Connecting $connectionId with thing $thingId');
      AppLogger.debug('  Managing ${managedThingIds.length} things');

      final client = MqttServerClient.withPort(endpoint, thingId, 8883);
      client.secure = true;
      client.keepAlivePeriod = 30;
      client.autoReconnect = true;
      client.onAutoReconnect = () => _onAutoReconnect(connectionId);
      client.onAutoReconnected = () => _onAutoReconnected(connectionId);
      client.onConnected = () => _onConnected(connectionId);
      client.onDisconnected = () => _onDisconnected(connectionId);
      client.logging(on: false); // Set to true for debugging

      // Set up security context
      final context = SecurityContext(withTrustedRoots: false);
      context.useCertificateChain(certPath);
      context.usePrivateKey(keyPath);
      context.setTrustedCertificates(caPath);
      client.securityContext = context;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(thingId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
      client.connectionMessage = connMessage;

      AppLogger.info(
          'Connecting to AWS IoT: $endpoint as $thingId (conn: $connectionId)');

      await client.connect();

      // Wait for connection callback
      await Future.delayed(const Duration(milliseconds: 100));

      // Check if connected - mqtt_client uses its own MqttConnectionState enum
      final isClientConnected = client.connectionStatus?.state ==
          MqttConnectionState.connected;
      if (connection.connectionState == ConnectionState.connected ||
          isClientConnected) {
        connection.client = client;

        if (connection.connectionState != ConnectionState.connected) {
          _updateConnectionState(connectionId, ConnectionState.connected);
        }

        _setupMessageListener(connectionId, client);

        // Subscribe to shadow deltas for all managed things in the rack
        for (final managedThing in managedThingIds) {
          await _subscribeShadowDelta(client, managedThing);
        }

        AppLogger.info(
            'Connected $connectionId, managing ${managedThingIds.length} things');
        return true;
      }

      AppLogger.warning('Connection failed for $connectionId');
      _updateConnectionState(connectionId, ConnectionState.disconnected);
      return false;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to connect $connectionId', e, stackTrace);
      _updateConnectionState(connectionId, ConnectionState.disconnected);
      return false;
    }
  }

  /// Subscribe to shadow delta for a thing
  Future<void> _subscribeShadowDelta(
      MqttServerClient client, String thingId) async {
    final topic = AwsConstants.shadowDeltaTopic(thingId);
    client.subscribe(topic, MqttQos.atLeastOnce);
    AppLogger.debug('Subscribed to shadow delta: $topic');
  }

  /// Set up message listener for a connection
  void _setupMessageListener(String connectionId, MqttServerClient client) {
    client.updates!
        .listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final message in messages) {
        final topic = message.topic;
        final payload = message.payload as MqttPublishMessage;
        final payloadString = MqttPublishPayload.bytesToStringAsString(
          payload.payload.message,
        );

        AppLogger.debug('[$connectionId] Received on $topic: $payloadString');

        // Parse shadow delta messages
        if (topic.contains('/shadow/update/delta')) {
          final thingId = _extractThingIdFromTopic(topic);
          if (thingId != null) {
            try {
              final delta = jsonDecode(payloadString) as Map<String, dynamic>;
              _shadowDeltaController.add((thingId, delta));
            } catch (e) {
              AppLogger.error('Failed to parse shadow delta', e);
            }
          }
        }
      }
    });
  }

  String? _extractThingIdFromTopic(String topic) {
    final regex = RegExp(r'\$aws/things/([^/]+)/shadow');
    final match = regex.firstMatch(topic);
    return match?.group(1);
  }

  /// Publish shadow update for a thing
  Future<void> publishShadowUpdate(
    String thingId,
    Map<String, dynamic> reportedState,
  ) async {
    // Find the connection that manages this thing
    MqttConnection? connection;
    for (final conn in _connections.values) {
      if (conn.managedThingIds.contains(thingId) && conn.isConnected) {
        connection = conn;
        break;
      }
    }

    if (connection == null || connection.client == null) {
      AppLogger.warning('No active connection for thing $thingId');
      return;
    }

    final topic = AwsConstants.shadowUpdateTopic(thingId);
    final payload = jsonEncode({
      'state': {
        'reported': reportedState,
        'desired': null,
      },
    });

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    connection.client!
        .publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    AppLogger.debug(
        '[${connection.connectionId}] Published shadow for $thingId');
  }

  /// Request shadow state for a thing
  Future<void> getShadow(String thingId) async {
    MqttConnection? connection;
    for (final conn in _connections.values) {
      if (conn.managedThingIds.contains(thingId) && conn.isConnected) {
        connection = conn;
        break;
      }
    }

    if (connection == null || connection.client == null) {
      AppLogger.warning('No active connection for thing $thingId');
      return;
    }

    final client = connection.client!;

    // Subscribe to get/accepted and get/rejected
    final acceptedTopic = AwsConstants.shadowGetAcceptedTopic(thingId);
    final rejectedTopic = AwsConstants.shadowGetRejectedTopic(thingId);

    client.subscribe(acceptedTopic, MqttQos.atLeastOnce);
    client.subscribe(rejectedTopic, MqttQos.atLeastOnce);

    // Publish empty message to get topic
    final getTopic = AwsConstants.shadowGetTopic(thingId);
    final builder = MqttClientPayloadBuilder();
    builder.addString('{}');

    client.publishMessage(getTopic, MqttQos.atLeastOnce, builder.payload!);
    AppLogger.debug('[${connection.connectionId}] Requested shadow for $thingId');
  }

  /// Disconnect all connections
  void disconnectAll() {
    for (final connectionId in _connections.keys.toList()) {
      _disconnectSingle(connectionId);
    }
    _connections.clear();
    _updateGlobalState();
    AppLogger.info('Disconnected all connections');
  }

  /// Disconnect a single connection
  void _disconnectSingle(String connectionId) {
    final connection = _connections[connectionId];
    if (connection == null) return;

    if (connection.client != null) {
      try {
        connection.client!.disconnect();
      } catch (e) {
        AppLogger.debug('Error disconnecting $connectionId: $e');
      }
    }

    _updateConnectionState(connectionId, ConnectionState.disconnected);
    AppLogger.info('Disconnected $connectionId');
  }

  /// Check if a thing is connected (has an active connection managing it)
  bool isThingConnected(String thingId) {
    for (final conn in _connections.values) {
      if (conn.managedThingIds.contains(thingId) && conn.isConnected) {
        return true;
      }
    }
    return false;
  }

  void _updateConnectionState(String connectionId, ConnectionState state) {
    final connection = _connections[connectionId];
    if (connection != null) {
      connection.connectionState = state;
    }
    _connectionStateController.add((connectionId, state));
    _updateGlobalState();
  }

  void _updateGlobalState() {
    final hasConnected =
        _connections.values.any((c) => c.isConnected);
    final hasConnecting = _connections.values
        .any((c) => c.connectionState == ConnectionState.connecting);

    if (hasConnected) {
      _globalStateController.add(ConnectionState.connected);
    } else if (hasConnecting) {
      _globalStateController.add(ConnectionState.connecting);
    } else {
      _globalStateController.add(ConnectionState.disconnected);
    }
  }

  void _onConnected(String connectionId) {
    AppLogger.info('[$connectionId] Connected');
    _updateConnectionState(connectionId, ConnectionState.connected);
  }

  void _onDisconnected(String connectionId) {
    AppLogger.info('[$connectionId] Disconnected');
    _updateConnectionState(connectionId, ConnectionState.disconnected);
  }

  void _onAutoReconnect(String connectionId) {
    AppLogger.info('[$connectionId] Auto-reconnecting...');
    _updateConnectionState(connectionId, ConnectionState.connecting);
  }

  void _onAutoReconnected(String connectionId) {
    AppLogger.info('[$connectionId] Auto-reconnected');
    _updateConnectionState(connectionId, ConnectionState.connected);

    // Re-subscribe to shadow deltas after reconnection (subscriptions lost due to clean session)
    final connection = _connections[connectionId];
    if (connection != null && connection.client != null) {
      for (final managedThing in connection.managedThingIds) {
        _subscribeShadowDelta(connection.client!, managedThing);
      }
    }
  }

  /// Dispose resources
  void dispose() {
    disconnectAll();
    _connectionStateController.close();
    _shadowDeltaController.close();
    _globalStateController.close();
  }
}
