import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/constants/aws_constants.dart';
import '../core/utils/logger.dart';

/// Connection state for MQTT client
enum MqttConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

/// Callback type for shadow delta messages
typedef ShadowDeltaCallback = void Function(
  String thingId,
  Map<String, dynamic> delta,
);

/// Service for managing MQTT connections to AWS IoT Core
class MqttService {
  MqttService._();

  static final MqttService instance = MqttService._();

  MqttServerClient? _client;
  MqttConnectionState _connectionState = MqttConnectionState.disconnected;

  final _connectionStateController =
      StreamController<MqttConnectionState>.broadcast();
  final _shadowDeltaController =
      StreamController<(String, Map<String, dynamic>)>.broadcast();

  /// Stream of connection state changes
  Stream<MqttConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Stream of shadow delta messages
  Stream<(String, Map<String, dynamic>)> get shadowDeltaStream =>
      _shadowDeltaController.stream;

  /// Current connection state
  MqttConnectionState get connectionState => _connectionState;

  /// Whether the client is connected
  bool get isConnected => _connectionState == MqttConnectionState.connected;

  /// Connect to AWS IoT Core
  Future<bool> connect({
    required String endpoint,
    required String clientId,
    required String certPath,
    required String keyPath,
    required String caPath,
  }) async {
    if (_connectionState == MqttConnectionState.connected) {
      AppLogger.warning('Already connected');
      return true;
    }

    _updateConnectionState(MqttConnectionState.connecting);

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

      AppLogger.debug('Using cert: $certPath');
      AppLogger.debug('Using key: $keyPath');
      AppLogger.debug('Using CA: $caPath');

      _client = MqttServerClient.withPort(endpoint, clientId, 8883);
      _client!.secure = true;
      _client!.keepAlivePeriod = 30;
      _client!.autoReconnect = true;
      _client!.onAutoReconnect = _onAutoReconnect;
      _client!.onAutoReconnected = _onAutoReconnected;
      _client!.onConnected = _onConnected;
      _client!.onDisconnected = _onDisconnected;
      _client!.logging(on: true);  // Enable for debugging

      // Set up security context with certificates - create new context to avoid shared state issues
      final context = SecurityContext(withTrustedRoots: false);
      context.useCertificateChain(certPath);
      context.usePrivateKey(keyPath);
      context.setTrustedCertificates(caPath);

      _client!.securityContext = context;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);

      _client!.connectionMessage = connMessage;

      AppLogger.info('Connecting to AWS IoT: $endpoint with client ID: $clientId');

      try {
        await _client!.connect();
      } catch (e) {
        AppLogger.error('MQTT connect() threw: $e');
        AppLogger.debug('Connection status: ${_client!.connectionStatus}');
        rethrow;
      }

      // Wait a short time for the connection callbacks to fire
      await Future.delayed(const Duration(milliseconds: 100));

      // Check our own connection state (updated by _onConnected callback)
      // or the client's connection status
      final clientState = _client!.connectionStatus?.state;
      AppLogger.debug('Client connection state: $clientState, our state: $_connectionState');

      if (_connectionState == MqttConnectionState.connected ||
          clientState == MqttConnectionState.connected) {
        if (_connectionState != MqttConnectionState.connected) {
          _updateConnectionState(MqttConnectionState.connected);
        }
        _setupMessageListener();
        AppLogger.info('Connected to AWS IoT');
        return true;
      }

      AppLogger.warning('MQTT connection failed. Client state: $clientState, our state: $_connectionState');
      _updateConnectionState(MqttConnectionState.disconnected);
      return false;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to connect to AWS IoT', e, stackTrace);
      _updateConnectionState(MqttConnectionState.disconnected);
      return false;
    }
  }

  /// Disconnect from AWS IoT Core
  void disconnect() {
    if (_client != null) {
      _updateConnectionState(MqttConnectionState.disconnecting);
      _client!.disconnect();
      _client = null;
      _updateConnectionState(MqttConnectionState.disconnected);
      AppLogger.info('Disconnected from AWS IoT');
    }
  }

  /// Subscribe to shadow delta for a thing
  Future<void> subscribeShadowDelta(String thingId) async {
    if (!isConnected) {
      AppLogger.warning('Cannot subscribe: not connected');
      return;
    }

    final topic = AwsConstants.shadowDeltaTopic(thingId);
    _client!.subscribe(topic, MqttQos.atLeastOnce);
    AppLogger.debug('Subscribed to shadow delta: $topic');
  }

  /// Unsubscribe from shadow delta for a thing
  void unsubscribeShadowDelta(String thingId) {
    if (_client == null) return;

    final topic = AwsConstants.shadowDeltaTopic(thingId);
    _client!.unsubscribe(topic);
    AppLogger.debug('Unsubscribed from shadow delta: $topic');
  }

  /// Publish shadow update (reported state)
  Future<void> publishShadowUpdate(
    String thingId,
    Map<String, dynamic> reportedState,
  ) async {
    if (!isConnected) {
      AppLogger.warning('Cannot publish: not connected');
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

    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    AppLogger.debug('Published shadow update for $thingId: $payload');
  }

  /// Request current shadow state
  Future<void> getShadow(String thingId) async {
    if (!isConnected) {
      AppLogger.warning('Cannot get shadow: not connected');
      return;
    }

    // Subscribe to get/accepted and get/rejected
    final acceptedTopic = AwsConstants.shadowGetAcceptedTopic(thingId);
    final rejectedTopic = AwsConstants.shadowGetRejectedTopic(thingId);

    _client!.subscribe(acceptedTopic, MqttQos.atLeastOnce);
    _client!.subscribe(rejectedTopic, MqttQos.atLeastOnce);

    // Publish empty message to get topic
    final getTopic = AwsConstants.shadowGetTopic(thingId);
    final builder = MqttClientPayloadBuilder();
    builder.addString('{}');

    _client!.publishMessage(getTopic, MqttQos.atLeastOnce, builder.payload!);
    AppLogger.debug('Requested shadow for $thingId');
  }

  void _setupMessageListener() {
    _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final message in messages) {
        final topic = message.topic;
        final payload = message.payload as MqttPublishMessage;
        final payloadString = MqttPublishPayload.bytesToStringAsString(
          payload.payload.message,
        );

        AppLogger.debug('Received message on $topic: $payloadString');

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
    // Topic format: $aws/things/{thingId}/shadow/...
    final regex = RegExp(r'\$aws/things/([^/]+)/shadow');
    final match = regex.firstMatch(topic);
    return match?.group(1);
  }

  void _updateConnectionState(MqttConnectionState state) {
    _connectionState = state;
    _connectionStateController.add(state);
  }

  void _onConnected() {
    AppLogger.info('MQTT connected');
    _updateConnectionState(MqttConnectionState.connected);
  }

  void _onDisconnected() {
    AppLogger.info('MQTT disconnected');
    _updateConnectionState(MqttConnectionState.disconnected);
  }

  void _onAutoReconnect() {
    AppLogger.info('MQTT auto-reconnecting...');
    _updateConnectionState(MqttConnectionState.connecting);
  }

  void _onAutoReconnected() {
    AppLogger.info('MQTT auto-reconnected');
    _updateConnectionState(MqttConnectionState.connected);
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _connectionStateController.close();
    _shadowDeltaController.close();
  }
}
