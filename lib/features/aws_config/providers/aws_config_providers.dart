import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/utils/logger.dart';
import '../../../services/aws_iot_service.dart';
import '../../../services/storage_service.dart';

/// URL for Amazon Root CA 1
const _amazonRootCaUrl = 'https://www.amazontrust.com/repository/AmazonRootCA1.pem';

/// Represents the state of AWS configuration
class AwsConfigState {
  final String? activeProfileName;
  final Map<String, dynamic>? activeProfileCredentials;
  final String? iotEndpoint;
  final String? iotPolicyName;
  final bool isConnecting;
  final bool isConnected;
  final String? lastError;
  final List<String> availableProfiles;
  final bool hasCaCert;

  const AwsConfigState({
    this.activeProfileName,
    this.activeProfileCredentials,
    this.iotEndpoint,
    this.iotPolicyName,
    this.isConnecting = false,
    this.isConnected = false,
    this.lastError,
    this.availableProfiles = const [],
    this.hasCaCert = false,
  });

  AwsConfigState copyWith({
    String? activeProfileName,
    Map<String, dynamic>? activeProfileCredentials,
    String? iotEndpoint,
    String? iotPolicyName,
    bool? isConnecting,
    bool? isConnected,
    String? lastError,
    List<String>? availableProfiles,
    bool? hasCaCert,
    bool clearError = false,
    bool clearActiveProfile = false,
    bool clearEndpoint = false,
  }) {
    return AwsConfigState(
      activeProfileName:
          clearActiveProfile ? null : (activeProfileName ?? this.activeProfileName),
      activeProfileCredentials:
          clearActiveProfile ? null : (activeProfileCredentials ?? this.activeProfileCredentials),
      iotEndpoint: clearEndpoint ? null : (iotEndpoint ?? this.iotEndpoint),
      iotPolicyName: clearActiveProfile ? null : (iotPolicyName ?? this.iotPolicyName),
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      lastError: clearError ? null : lastError,
      availableProfiles: availableProfiles ?? this.availableProfiles,
      hasCaCert: hasCaCert ?? this.hasCaCert,
    );
  }

  bool get hasActiveProfile => activeProfileName != null;
  bool get hasEndpoint => iotEndpoint != null && iotEndpoint!.isNotEmpty;
  bool get hasPolicyName => iotPolicyName != null && iotPolicyName!.isNotEmpty;
}

/// Provider for managing AWS configuration state
class AwsConfigNotifier extends StateNotifier<AwsConfigState> {
  final AwsIotService _iotService;

  AwsConfigNotifier(this._iotService) : super(const AwsConfigState()) {
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    try {
      final profiles = await StorageService.instance.listAwsProfiles();
      final activeProfileName = StorageService.instance.getActiveAwsProfile();
      final hasCaCert = await StorageService.instance.caCertExists();
      Map<String, dynamic>? credentials;
      String? endpoint;
      String? policyName;

      if (activeProfileName != null) {
        credentials = await StorageService.instance.loadAwsProfile(activeProfileName);
        endpoint = credentials?['endpoint'] as String?;
        policyName = credentials?['policyName'] as String?;

        // Initialize the AWS IoT service with saved credentials
        if (credentials != null) {
          _iotService.initialize(
            region: credentials['region'] as String? ?? 'eu-west-1',
            accessKeyId: credentials['accessKeyId'] as String? ?? '',
            secretAccessKey: credentials['secretAccessKey'] as String? ?? '',
            iotEndpoint: endpoint,
          );
        }
      }

      state = state.copyWith(
        availableProfiles: profiles,
        activeProfileName: activeProfileName,
        activeProfileCredentials: credentials,
        iotEndpoint: endpoint,
        iotPolicyName: policyName,
        hasCaCert: hasCaCert,
      );
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load AWS config state', e, stackTrace);
      state = state.copyWith(lastError: e.toString());
    }
  }

  /// Refresh the list of available profiles
  Future<void> refreshProfiles() async {
    final profiles = await StorageService.instance.listAwsProfiles();
    state = state.copyWith(availableProfiles: profiles);
  }

  /// Set the active AWS profile
  Future<void> setActiveProfile(String profileName) async {
    try {
      state = state.copyWith(isConnecting: true, clearError: true);

      final credentials = await StorageService.instance.loadAwsProfile(profileName);
      if (credentials == null) {
        throw Exception('Profile not found: $profileName');
      }

      // Save as active profile
      await StorageService.instance.setActiveAwsProfile(profileName);

      // Initialize the AWS IoT service with new credentials
      final endpoint = credentials['endpoint'] as String?;
      final policyName = credentials['policyName'] as String?;
      _iotService.initialize(
        region: credentials['region'] as String? ?? 'eu-west-1',
        accessKeyId: credentials['accessKeyId'] as String? ?? '',
        secretAccessKey: credentials['secretAccessKey'] as String? ?? '',
        iotEndpoint: endpoint,
      );

      state = state.copyWith(
        activeProfileName: profileName,
        activeProfileCredentials: credentials,
        iotEndpoint: endpoint,
        iotPolicyName: policyName,
        isConnecting: false,
        isConnected: false, // Not yet connected to MQTT
      );

      AppLogger.info('Switched to AWS profile: $profileName');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to set active profile', e, stackTrace);
      state = state.copyWith(
        isConnecting: false,
        lastError: e.toString(),
      );
      rethrow;
    }
  }

  /// Clear the active profile
  Future<void> clearActiveProfile() async {
    await StorageService.instance.clearActiveAwsProfile();
    state = state.copyWith(
      clearActiveProfile: true,
      clearEndpoint: true,
      isConnected: false,
    );
  }

  /// Discover the IoT endpoint
  Future<String> discoverEndpoint() async {
    try {
      state = state.copyWith(isConnecting: true, clearError: true);

      if (!_iotService.isInitialized) {
        throw Exception('AWS credentials not configured. Set an active profile first.');
      }

      final endpoint = await _iotService.describeEndpoint();

      // Update the saved profile with the discovered endpoint
      if (state.activeProfileName != null && state.activeProfileCredentials != null) {
        final updatedCredentials = Map<String, dynamic>.from(state.activeProfileCredentials!);
        updatedCredentials['endpoint'] = endpoint;
        await StorageService.instance.saveAwsProfile(
          state.activeProfileName!,
          updatedCredentials,
        );

        state = state.copyWith(
          iotEndpoint: endpoint,
          activeProfileCredentials: updatedCredentials,
          isConnecting: false,
        );
      } else {
        state = state.copyWith(
          iotEndpoint: endpoint,
          isConnecting: false,
        );
      }

      AppLogger.info('Discovered IoT endpoint: $endpoint');
      return endpoint;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to discover endpoint', e, stackTrace);
      state = state.copyWith(
        isConnecting: false,
        lastError: e.toString(),
      );
      rethrow;
    }
  }

  /// Test the AWS connection by listing things
  Future<bool> testConnection() async {
    try {
      state = state.copyWith(isConnecting: true, clearError: true);

      if (!_iotService.isInitialized) {
        throw Exception('AWS credentials not configured. Set an active profile first.');
      }

      // Try to list things as a connection test
      await _iotService.listThings(maxResults: 1);

      state = state.copyWith(
        isConnecting: false,
        isConnected: true,
      );

      AppLogger.info('AWS connection test successful');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('AWS connection test failed', e, stackTrace);
      state = state.copyWith(
        isConnecting: false,
        isConnected: false,
        lastError: e.toString(),
      );
      return false;
    }
  }

  /// Clear the last error
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Save the IoT policy name for the current profile
  Future<void> savePolicyName(String policyName) async {
    if (state.activeProfileName == null || state.activeProfileCredentials == null) {
      throw Exception('No active profile to save policy name to');
    }

    final updatedCredentials = Map<String, dynamic>.from(state.activeProfileCredentials!);
    updatedCredentials['policyName'] = policyName;

    await StorageService.instance.saveAwsProfile(
      state.activeProfileName!,
      updatedCredentials,
    );

    state = state.copyWith(
      iotPolicyName: policyName,
      activeProfileCredentials: updatedCredentials,
    );

    AppLogger.info('Saved IoT policy name: $policyName');
  }

  /// Check if CA certificate exists
  Future<void> checkCaCert() async {
    final exists = await StorageService.instance.caCertExists();
    state = state.copyWith(hasCaCert: exists);
  }

  /// Download the Amazon Root CA certificate
  Future<bool> downloadCaCert() async {
    try {
      state = state.copyWith(isConnecting: true, clearError: true);

      AppLogger.info('Downloading Amazon Root CA certificate...');

      final response = await http.get(Uri.parse(_amazonRootCaUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download CA certificate: HTTP ${response.statusCode}');
      }

      final certContent = response.body;

      // Validate that it looks like a certificate
      if (!certContent.contains('-----BEGIN CERTIFICATE-----')) {
        throw Exception('Downloaded content does not appear to be a valid certificate');
      }

      // Save to storage
      await StorageService.instance.saveCaCert(certContent);

      state = state.copyWith(
        isConnecting: false,
        hasCaCert: true,
      );

      AppLogger.info('Successfully downloaded and saved CA certificate');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to download CA certificate', e, stackTrace);
      state = state.copyWith(
        isConnecting: false,
        lastError: e.toString(),
      );
      return false;
    }
  }
}

/// Global AWS IoT service instance
final awsIotServiceProvider = Provider<AwsIotService>((ref) {
  return AwsIotService();
});

/// AWS configuration state provider
final awsConfigProvider =
    StateNotifierProvider<AwsConfigNotifier, AwsConfigState>((ref) {
  final iotService = ref.watch(awsIotServiceProvider);
  return AwsConfigNotifier(iotService);
});

/// Convenience provider for checking if AWS is configured
final isAwsConfiguredProvider = Provider<bool>((ref) {
  final state = ref.watch(awsConfigProvider);
  return state.hasActiveProfile;
});

/// Convenience provider for the active profile name
final activeAwsProfileProvider = Provider<String?>((ref) {
  return ref.watch(awsConfigProvider).activeProfileName;
});

/// Convenience provider for the IoT endpoint
final iotEndpointProvider = Provider<String?>((ref) {
  return ref.watch(awsConfigProvider).iotEndpoint;
});

/// Convenience provider for the IoT policy name
final iotPolicyNameProvider = Provider<String?>((ref) {
  return ref.watch(awsConfigProvider).iotPolicyName;
});

/// Convenience provider for CA certificate status
final hasCaCertProvider = Provider<bool>((ref) {
  return ref.watch(awsConfigProvider).hasCaCert;
});
