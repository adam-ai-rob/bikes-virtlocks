import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/aws_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../services/aws_iot_service.dart';
import '../../../services/storage_service.dart';
import '../../aws_config/providers/aws_config_providers.dart';

/// Represents a Thing with local and remote state
class ThingModel {
  final String thingName;
  final String? thingArn;
  final String? thingTypeName;
  final Map<String, String> attributes;
  final bool hasLocalCertificates;

  ThingModel({
    required this.thingName,
    this.thingArn,
    this.thingTypeName,
    this.attributes = const {},
    this.hasLocalCertificates = false,
  });

  factory ThingModel.fromThingAttribute(
    ThingAttribute attr, {
    bool hasLocalCertificates = false,
  }) {
    return ThingModel(
      thingName: attr.thingName,
      thingArn: attr.thingArn,
      thingTypeName: attr.thingTypeName,
      attributes: attr.attributes,
      hasLocalCertificates: hasLocalCertificates,
    );
  }

  /// Get the environment from thing name (e.g., "dev-rack1-bike1" -> "dev")
  String? get environment {
    final parts = thingName.split('-');
    if (parts.isNotEmpty) {
      final env = parts.first.toLowerCase();
      if (['dev', 'test', 'prod', 'staging'].contains(env)) {
        return env;
      }
    }
    return attributes['environment'];
  }

  /// Get the device type from attributes or thing name
  String? get deviceType {
    if (attributes.containsKey('type')) {
      return attributes['type'];
    }
    // Try to infer from thing name
    final nameLower = thingName.toLowerCase();
    if (nameLower.contains('bike')) return 'bike';
    if (nameLower.contains('scooter')) return 'scooter';
    if (nameLower.contains('master')) return 'master';
    return null;
  }

  /// Check if this is a master device (rack controller)
  bool get isMaster => deviceType == 'master' || thingName.contains('master');

  /// Get the enabled status
  bool get isEnabled => attributes['enabled']?.toLowerCase() == 'true';

  /// Get the lobby/location
  String? get lobby => attributes['lobby'];

  ThingModel copyWith({
    String? thingName,
    String? thingArn,
    String? thingTypeName,
    Map<String, String>? attributes,
    bool? hasLocalCertificates,
  }) {
    return ThingModel(
      thingName: thingName ?? this.thingName,
      thingArn: thingArn ?? this.thingArn,
      thingTypeName: thingTypeName ?? this.thingTypeName,
      attributes: attributes ?? this.attributes,
      hasLocalCertificates: hasLocalCertificates ?? this.hasLocalCertificates,
    );
  }
}

/// Filter options for things list
class ThingsFilter {
  final String? environment;
  final String? deviceType;
  final String? searchQuery;
  final bool showOnlyWithCertificates;

  const ThingsFilter({
    this.environment,
    this.deviceType,
    this.searchQuery,
    this.showOnlyWithCertificates = false,
  });

  ThingsFilter copyWith({
    String? environment,
    String? deviceType,
    String? searchQuery,
    bool? showOnlyWithCertificates,
    bool clearEnvironment = false,
    bool clearDeviceType = false,
    bool clearSearchQuery = false,
  }) {
    return ThingsFilter(
      environment: clearEnvironment ? null : (environment ?? this.environment),
      deviceType: clearDeviceType ? null : (deviceType ?? this.deviceType),
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      showOnlyWithCertificates:
          showOnlyWithCertificates ?? this.showOnlyWithCertificates,
    );
  }

  bool matches(ThingModel thing) {
    if (environment != null && thing.environment != environment) {
      return false;
    }
    if (deviceType != null && thing.deviceType != deviceType) {
      return false;
    }
    if (searchQuery != null && searchQuery!.isNotEmpty) {
      final query = searchQuery!.toLowerCase();
      if (!thing.thingName.toLowerCase().contains(query)) {
        return false;
      }
    }
    if (showOnlyWithCertificates && !thing.hasLocalCertificates) {
      return false;
    }
    return true;
  }
}

/// State for things management
class ThingsState {
  final List<ThingModel> things;
  final ThingsFilter filter;
  final bool isLoading;
  final String? error;
  final ThingModel? selectedThing;

  const ThingsState({
    this.things = const [],
    this.filter = const ThingsFilter(),
    this.isLoading = false,
    this.error,
    this.selectedThing,
  });

  List<ThingModel> get filteredThings =>
      things.where((t) => filter.matches(t)).toList();

  /// Get unique environments from the things list
  Set<String> get availableEnvironments =>
      things.map((t) => t.environment).whereType<String>().toSet();

  /// Get unique device types from the things list
  Set<String> get availableDeviceTypes =>
      things.map((t) => t.deviceType).whereType<String>().toSet();

  ThingsState copyWith({
    List<ThingModel>? things,
    ThingsFilter? filter,
    bool? isLoading,
    String? error,
    ThingModel? selectedThing,
    bool clearError = false,
    bool clearSelectedThing = false,
  }) {
    return ThingsState(
      things: things ?? this.things,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error,
      selectedThing:
          clearSelectedThing ? null : (selectedThing ?? this.selectedThing),
    );
  }
}

/// Notifier for managing things state
class ThingsNotifier extends StateNotifier<ThingsState> {
  final AwsIotService _iotService;
  final Ref _ref;

  ThingsNotifier(this._iotService, this._ref) : super(const ThingsState());

  /// Load things from AWS IoT
  Future<void> loadThings() async {
    final awsConfig = _ref.read(awsConfigProvider);
    if (!awsConfig.hasActiveProfile) {
      state = state.copyWith(
        error: 'No AWS profile configured. Please configure AWS credentials first.',
        isLoading: false,
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Get things from AWS
      final thingAttributes = await _iotService.listThings(maxResults: 250);

      // Get local things to check for certificates
      final localThings = await StorageService.instance.listLocalThings();
      final localThingSet = localThings.toSet();

      // Convert to ThingModel
      final things = thingAttributes.map((attr) {
        return ThingModel.fromThingAttribute(
          attr,
          hasLocalCertificates: localThingSet.contains(attr.thingName),
        );
      }).toList();

      // Sort by name
      things.sort((a, b) => a.thingName.compareTo(b.thingName));

      state = state.copyWith(
        things: things,
        isLoading: false,
      );

      AppLogger.info('Loaded ${things.length} things from AWS');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load things', e, stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Update the filter
  void updateFilter(ThingsFilter filter) {
    state = state.copyWith(filter: filter);
  }

  /// Set the selected thing
  void selectThing(ThingModel? thing) {
    state = state.copyWith(
      selectedThing: thing,
      clearSelectedThing: thing == null,
    );
  }

  /// Create a new thing
  Future<ThingModel?> createThing({
    required String thingName,
    required String environment,
    String? thingTypeName,
    Map<String, String>? attributes,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final result = await _iotService.createThingWithCertificate(
        thingName: thingName,
        environment: environment,
        thingTypeName: thingTypeName,
        attributes: attributes,
      );

      // Save certificates locally
      await StorageService.instance.saveThingCertificates(
        thingName,
        certificatePem: result.certificate.certificatePem,
        privateKey: result.certificate.privateKey,
        publicKey: result.certificate.publicKey,
      );

      // Save thing config
      await StorageService.instance.saveThingConfig(thingName, {
        'thingArn': result.thing.thingArn,
        'certificateArn': result.certificate.certificateArn,
        'certificateId': result.certificate.certificateId,
        'environment': environment,
        'attributes': attributes,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Reload things
      await loadThings();

      AppLogger.info('Created thing: $thingName');
      return state.things.firstWhere((t) => t.thingName == thingName);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create thing', e, stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      return null;
    }
  }

  /// Delete a thing
  Future<bool> deleteThing(String thingName) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Delete from AWS
      await _iotService.deleteThingWithCertificates(thingName);

      // Delete local certificates
      await StorageService.instance.deleteThingCertificates(thingName);

      // Reload things
      await loadThings();

      AppLogger.info('Deleted thing: $thingName');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete thing', e, stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Clear the error
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Update thing attributes
  Future<bool> updateThingAttributes({
    required String thingName,
    required Map<String, String> attributes,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Update in AWS
      await _iotService.updateThing(
        thingName: thingName,
        attributes: attributes,
      );

      // Update local config if exists
      final config = await StorageService.instance.loadThingConfig(thingName);
      if (config != null) {
        config['attributes'] = attributes;
        await StorageService.instance.saveThingConfig(thingName, config);
      }

      // Reload things
      await loadThings();

      AppLogger.info('Updated thing attributes: $thingName');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update thing attributes', e, stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Create a rack with master and lock things
  /// All things in the rack share the same certificate for simplicity
  Future<RackCreationResult?> createRack({
    required String environment,
    required String rackName,
    required int bikeLockCount,
    int scooterLockCount = 0,
    String? lobby,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    final createdThings = <String>[];
    final errors = <String>[];

    try {
      // 1. Create shared certificate first
      AppLogger.info('Creating shared certificate for rack: $rackName');
      final certResult = await _iotService.createKeysAndCertificate();

      // 2. Create master thing
      final masterName = AwsConstants.masterThingName(environment, rackName);
      AppLogger.info('Creating master: $masterName');

      try {
        final masterType = _getMasterThingType(environment);
        await _iotService.createThing(
          thingName: masterName,
          thingTypeName: masterType,
          attributes: {
            'enabled': 'true',
            'type': 'master',
            'environment': environment,
            if (lobby != null) 'lobby': lobby,
          },
        );

        // Attach certificate to master
        await _iotService.attachThingPrincipal(
          thingName: masterName,
          principal: certResult.certificateArn,
        );

        // Attach policy
        await _iotService.attachPolicy(
          policyName: AwsConstants.iotPolicyName(environment),
          target: certResult.certificateArn,
        );

        // Save master certificates locally
        await StorageService.instance.saveThingCertificates(
          masterName,
          certificatePem: certResult.certificatePem,
          privateKey: certResult.privateKey,
          publicKey: certResult.publicKey,
        );

        await StorageService.instance.saveThingConfig(masterName, {
          'certificateArn': certResult.certificateArn,
          'certificateId': certResult.certificateId,
          'environment': environment,
          'rackName': rackName,
          'type': 'master',
          'createdAt': DateTime.now().toIso8601String(),
        });

        createdThings.add(masterName);
      } catch (e) {
        errors.add('Failed to create master $masterName: $e');
        AppLogger.error('Failed to create master', e);
      }

      // 3. Create bike locks
      final lockType = _getLockThingType(environment);
      for (int i = 1; i <= bikeLockCount; i++) {
        final lockName = AwsConstants.lockThingName(environment, rackName, i);
        AppLogger.info('Creating bike lock: $lockName');

        try {
          await _iotService.createThing(
            thingName: lockName,
            thingTypeName: lockType,
            attributes: {
              'enabled': 'true',
              'type': 'bike',
              'environment': environment,
              if (lobby != null) 'lobby': lobby,
            },
          );

          // Attach shared certificate
          await _iotService.attachThingPrincipal(
            thingName: lockName,
            principal: certResult.certificateArn,
          );

          // Save lock certificates locally
          await StorageService.instance.saveThingCertificates(
            lockName,
            certificatePem: certResult.certificatePem,
            privateKey: certResult.privateKey,
            publicKey: certResult.publicKey,
          );

          await StorageService.instance.saveThingConfig(lockName, {
            'certificateArn': certResult.certificateArn,
            'certificateId': certResult.certificateId,
            'environment': environment,
            'rackName': rackName,
            'type': 'bike',
            'createdAt': DateTime.now().toIso8601String(),
          });

          createdThings.add(lockName);
        } catch (e) {
          errors.add('Failed to create lock $lockName: $e');
          AppLogger.error('Failed to create lock $lockName', e);
        }
      }

      // 4. Create scooter locks if requested
      for (int i = 1; i <= scooterLockCount; i++) {
        final index = bikeLockCount + i;
        final lockName = '${environment}-${rackName}-SCOOTER${i.toString().padLeft(2, '0')}';
        AppLogger.info('Creating scooter lock: $lockName');

        try {
          await _iotService.createThing(
            thingName: lockName,
            thingTypeName: lockType,
            attributes: {
              'enabled': 'true',
              'type': 'scooter',
              'environment': environment,
              if (lobby != null) 'lobby': lobby,
            },
          );

          // Attach shared certificate
          await _iotService.attachThingPrincipal(
            thingName: lockName,
            principal: certResult.certificateArn,
          );

          // Save lock certificates locally
          await StorageService.instance.saveThingCertificates(
            lockName,
            certificatePem: certResult.certificatePem,
            privateKey: certResult.privateKey,
            publicKey: certResult.publicKey,
          );

          await StorageService.instance.saveThingConfig(lockName, {
            'certificateArn': certResult.certificateArn,
            'certificateId': certResult.certificateId,
            'environment': environment,
            'rackName': rackName,
            'type': 'scooter',
            'createdAt': DateTime.now().toIso8601String(),
          });

          createdThings.add(lockName);
        } catch (e) {
          errors.add('Failed to create scooter lock $lockName: $e');
          AppLogger.error('Failed to create scooter lock $lockName', e);
        }
      }

      // Save rack configuration
      await StorageService.instance.saveRackConfig(
        environment,
        rackName,
        certificatePem: certResult.certificatePem,
        privateKey: certResult.privateKey,
        publicKey: certResult.publicKey,
        config: {
          'environment': environment,
          'rackName': rackName,
          'bikeLockCount': bikeLockCount,
          'scooterLockCount': scooterLockCount,
          'certificateArn': certResult.certificateArn,
          'certificateId': certResult.certificateId,
          'things': createdThings,
          'lobby': lobby,
          'createdAt': DateTime.now().toIso8601String(),
        },
      );

      // Reload things
      await loadThings();

      AppLogger.info('Created rack $rackName with ${createdThings.length} things');

      return RackCreationResult(
        rackName: rackName,
        environment: environment,
        createdThings: createdThings,
        errors: errors,
      );
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create rack', e, stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      return null;
    }
  }

  String _getMasterThingType(String environment) {
    switch (environment) {
      case 'dev':
        return AwsConstants.thingTypeRackMasterDev;
      case 'test':
        return AwsConstants.thingTypeRackMasterTest;
      case 'prod':
        return AwsConstants.thingTypeRackMasterProd;
      default:
        return AwsConstants.thingTypeRackMasterDev;
    }
  }

  String _getLockThingType(String environment) {
    switch (environment) {
      case 'dev':
        return AwsConstants.thingTypeBikeLockDev;
      case 'test':
        return AwsConstants.thingTypeBikeLockTest;
      case 'prod':
        return AwsConstants.thingTypeBikeLockProd;
      default:
        return AwsConstants.thingTypeBikeLockDev;
    }
  }

  /// Get all things that belong to a rack
  List<ThingModel> getRackThings(String environment, String rackName) {
    final prefix = '$environment-$rackName-';
    return state.things.where((t) => t.thingName.startsWith(prefix)).toList();
  }

  /// Get unique rack names from things
  Set<String> getUniqueRacks() {
    final racks = <String>{};
    for (final thing in state.things) {
      final parts = thing.thingName.split('-');
      if (parts.length >= 2) {
        // Format: env-rackname-device
        final rackName = '${parts[0]}-${parts[1]}';
        racks.add(rackName);
      }
    }
    return racks;
  }

  /// Delete a rack and all its things
  Future<RackDeletionResult> deleteRack({
    required String environment,
    required String rackName,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    final deletedThings = <String>[];
    final errors = <String>[];

    try {
      // Find all things in this rack
      final rackThings = getRackThings(environment, rackName);

      if (rackThings.isEmpty) {
        throw Exception('No things found for rack $environment-$rackName');
      }

      AppLogger.info(
          'Deleting rack $rackName with ${rackThings.length} things');

      // Delete each thing
      for (final thing in rackThings) {
        try {
          await _iotService.deleteThingWithCertificates(thing.thingName);
          await StorageService.instance.deleteThingCertificates(thing.thingName);
          deletedThings.add(thing.thingName);
          AppLogger.info('Deleted thing: ${thing.thingName}');
        } catch (e) {
          errors.add('Failed to delete ${thing.thingName}: $e');
          AppLogger.error('Failed to delete ${thing.thingName}', e);
        }
      }

      // Delete rack config if exists
      await StorageService.instance.deleteRackConfig(environment, rackName);

      // Reload things
      await loadThings();

      AppLogger.info(
          'Deleted rack $rackName: ${deletedThings.length} things deleted, ${errors.length} errors');

      return RackDeletionResult(
        rackName: rackName,
        environment: environment,
        deletedThings: deletedThings,
        errors: errors,
      );
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete rack', e, stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      return RackDeletionResult(
        rackName: rackName,
        environment: environment,
        deletedThings: deletedThings,
        errors: [...errors, e.toString()],
      );
    }
  }

  /// Download certificate for a thing from AWS IoT
  /// Returns the certificate PEM if successful, null otherwise
  /// Note: Private key cannot be downloaded from AWS - only available at creation time
  Future<CertificateDownloadResult?> downloadThingCertificate(String thingName) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Get the principals (certificate ARNs) attached to this thing
      final principals = await _iotService.listThingPrincipals(thingName);

      if (principals.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'No certificates attached to this thing',
        );
        return null;
      }

      // Get the first certificate (things typically have one)
      final certArn = principals.first;
      final certId = _iotService.getCertificateIdFromArn(certArn);

      // Describe the certificate to get the PEM
      final certDesc = await _iotService.describeCertificate(certId);

      if (certDesc.certificatePem == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'Certificate PEM not available',
        );
        return null;
      }

      // Save the certificate PEM locally (but warn that private key is missing)
      final thingDir = StorageService.instance.getThingDirectory(thingName);
      if (!await thingDir.exists()) {
        await thingDir.create(recursive: true);
      }

      // Save cert PEM
      final certPath = '${thingDir.path}/cert.pem';
      await File(certPath).writeAsString(certDesc.certificatePem!);

      // Save certificate info
      await StorageService.instance.saveThingConfig(thingName, {
        'certificateId': certDesc.certificateId,
        'certificateArn': certDesc.certificateArn,
        'status': certDesc.status,
        'downloadedAt': DateTime.now().toIso8601String(),
        'note': 'Private key not available - must be provided separately',
      });

      state = state.copyWith(isLoading: false);
      AppLogger.info('Downloaded certificate for thing: $thingName');

      // Reload things to update hasLocalCertificates status
      await loadThings();

      return CertificateDownloadResult(
        thingName: thingName,
        certificateId: certDesc.certificateId,
        certificateArn: certDesc.certificateArn,
        status: certDesc.status,
        certificatePem: certDesc.certificatePem!,
        hasPrivateKey: false,
      );
    } catch (e, stackTrace) {
      AppLogger.error('Failed to download certificate for $thingName', e, stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to download certificate: $e',
      );
      return null;
    }
  }

  /// Import a private key file for a thing
  /// The private key file should be in PEM format
  Future<bool> importPrivateKey(String thingName, String privateKeyPath) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final sourceFile = File(privateKeyPath);
      if (!await sourceFile.exists()) {
        state = state.copyWith(
          isLoading: false,
          error: 'Private key file not found: $privateKeyPath',
        );
        return false;
      }

      // Read the private key content
      final privateKeyContent = await sourceFile.readAsString();

      // Validate it looks like a PEM private key
      if (!privateKeyContent.contains('-----BEGIN') ||
          !privateKeyContent.contains('PRIVATE KEY')) {
        state = state.copyWith(
          isLoading: false,
          error: 'Invalid private key format. Expected PEM format.',
        );
        return false;
      }

      // Save to thing directory
      final thingDir = StorageService.instance.getThingDirectory(thingName);
      if (!await thingDir.exists()) {
        await thingDir.create(recursive: true);
      }

      final destPath = '${thingDir.path}/private.key';
      await File(destPath).writeAsString(privateKeyContent);

      AppLogger.info('Imported private key for thing: $thingName');

      // Reload things to update status
      await loadThings();

      state = state.copyWith(isLoading: false);
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to import private key for $thingName', e, stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to import private key: $e',
      );
      return false;
    }
  }

  /// Check if a thing has both certificate and private key
  Future<bool> hasCompleteCertificates(String thingName) async {
    return StorageService.instance.thingCertificatesExist(thingName);
  }
}

/// Result of certificate download
class CertificateDownloadResult {
  final String thingName;
  final String certificateId;
  final String certificateArn;
  final String status;
  final String certificatePem;
  final bool hasPrivateKey;

  CertificateDownloadResult({
    required this.thingName,
    required this.certificateId,
    required this.certificateArn,
    required this.status,
    required this.certificatePem,
    required this.hasPrivateKey,
  });
}

/// Result of rack creation operation
class RackCreationResult {
  final String rackName;
  final String environment;
  final List<String> createdThings;
  final List<String> errors;

  RackCreationResult({
    required this.rackName,
    required this.environment,
    required this.createdThings,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
  int get successCount => createdThings.length;
}

/// Result of rack deletion operation
class RackDeletionResult {
  final String rackName;
  final String environment;
  final List<String> deletedThings;
  final List<String> errors;

  RackDeletionResult({
    required this.rackName,
    required this.environment,
    required this.deletedThings,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
  int get successCount => deletedThings.length;
}

/// Provider for things management
final thingsProvider = StateNotifierProvider<ThingsNotifier, ThingsState>((ref) {
  final iotService = ref.watch(awsIotServiceProvider);
  return ThingsNotifier(iotService, ref);
});

/// Provider for filtered things (convenience)
final filteredThingsProvider = Provider<List<ThingModel>>((ref) {
  return ref.watch(thingsProvider).filteredThings;
});

/// Provider for things filter
final thingsFilterProvider = Provider<ThingsFilter>((ref) {
  return ref.watch(thingsProvider).filter;
});
