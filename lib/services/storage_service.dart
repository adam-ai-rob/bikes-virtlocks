import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/logger.dart';

/// Service for managing local file storage and configuration
class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  late Directory _configDir;
  late Box<dynamic> _settingsBox;

  bool _initialized = false;

  /// Get the configuration directory path
  Directory get configDir => _configDir;

  /// Initialize the storage service
  Future<void> initialize() async {
    if (_initialized) return;

    final appSupport = await getApplicationSupportDirectory();
    _configDir = Directory('${appSupport.path}/${AppConstants.configDirName}');

    // Create configuration directory structure
    await _createDirectoryStructure();

    // Open settings box
    _settingsBox = await Hive.openBox('settings');

    _initialized = true;
    AppLogger.info('Storage service initialized at: ${_configDir.path}');
  }

  /// Create the directory structure for configuration
  Future<void> _createDirectoryStructure() async {
    final dirs = [
      _configDir.path,
      '${_configDir.path}/${AppConstants.thingsDir}',
      '${_configDir.path}/${AppConstants.racksDir}',
      '${_configDir.path}/${AppConstants.profilesDir}',
    ];

    for (final dir in dirs) {
      final directory = Directory(dir);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        AppLogger.debug('Created directory: $dir');
      }
    }
  }

  // ============ Settings ============

  /// Get a setting value
  T? getSetting<T>(String key, {T? defaultValue}) {
    return _settingsBox.get(key, defaultValue: defaultValue) as T?;
  }

  /// Save a setting value
  Future<void> saveSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  /// Delete a setting
  Future<void> deleteSetting(String key) async {
    await _settingsBox.delete(key);
  }

  // ============ Things ============

  /// Get the directory for a thing
  Directory getThingDirectory(String thingId) {
    return Directory('${_configDir.path}/${AppConstants.thingsDir}/$thingId');
  }

  /// Check if thing certificates exist locally
  Future<bool> thingCertificatesExist(String thingId) async {
    final dir = getThingDirectory(thingId);
    if (!await dir.exists()) return false;

    final certFile = File('${dir.path}/${AppConstants.certPemFile}');
    final keyFile = File('${dir.path}/${AppConstants.privateKeyFile}');

    return await certFile.exists() && await keyFile.exists();
  }

  /// Save thing certificates
  Future<void> saveThingCertificates(
    String thingId, {
    required String certificatePem,
    required String privateKey,
    String? publicKey,
  }) async {
    final dir = getThingDirectory(thingId);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    await File('${dir.path}/${AppConstants.certPemFile}')
        .writeAsString(certificatePem);
    await File('${dir.path}/${AppConstants.privateKeyFile}')
        .writeAsString(privateKey);
    if (publicKey != null) {
      await File('${dir.path}/${AppConstants.publicKeyFile}')
          .writeAsString(publicKey);
    }

    AppLogger.info('Saved certificates for thing: $thingId');
  }

  /// Get thing certificate path
  String? getThingCertPath(String thingId) {
    final path =
        '${getThingDirectory(thingId).path}/${AppConstants.certPemFile}';
    if (File(path).existsSync()) return path;
    return null;
  }

  /// Get thing private key path
  String? getThingKeyPath(String thingId) {
    final path =
        '${getThingDirectory(thingId).path}/${AppConstants.privateKeyFile}';
    if (File(path).existsSync()) return path;
    return null;
  }

  /// Delete thing certificates
  Future<void> deleteThingCertificates(String thingId) async {
    final dir = getThingDirectory(thingId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      AppLogger.info('Deleted certificates for thing: $thingId');
    }
  }

  /// List all local things
  Future<List<String>> listLocalThings() async {
    final thingsDir =
        Directory('${_configDir.path}/${AppConstants.thingsDir}');
    if (!await thingsDir.exists()) return [];

    final entities = await thingsDir.list().toList();
    return entities
        .whereType<Directory>()
        .map((d) => d.path.split('/').last)
        .toList();
  }

  /// Save thing configuration
  Future<void> saveThingConfig(
    String thingId,
    Map<String, dynamic> config,
  ) async {
    final dir = getThingDirectory(thingId);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    await File('${dir.path}/${AppConstants.configJsonFile}')
        .writeAsString(jsonEncode(config));
  }

  /// Load thing configuration
  Future<Map<String, dynamic>?> loadThingConfig(String thingId) async {
    final file = File(
      '${getThingDirectory(thingId).path}/${AppConstants.configJsonFile}',
    );
    if (!await file.exists()) return null;

    final content = await file.readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  // ============ CA Certificate ============

  /// Get CA certificate path
  String get caCertPath => '${_configDir.path}/${AppConstants.caCertFile}';

  /// Check if CA certificate exists
  Future<bool> caCertExists() async {
    return File(caCertPath).exists();
  }

  /// Save CA certificate
  Future<void> saveCaCert(String certPem) async {
    await File(caCertPath).writeAsString(certPem);
    AppLogger.info('Saved CA certificate');
  }

  // ============ Racks ============

  /// Get rack directory
  Directory getRackDirectory(String env, String rackName) {
    return Directory(
      '${_configDir.path}/${AppConstants.racksDir}/$env-$rackName',
    );
  }

  /// Save rack configuration
  Future<void> saveRackConfig(
    String env,
    String rackName, {
    required String certificatePem,
    required String privateKey,
    String? publicKey,
    required Map<String, dynamic> config,
  }) async {
    final dir = getRackDirectory(env, rackName);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    await File('${dir.path}/${AppConstants.certPemFile}')
        .writeAsString(certificatePem);
    await File('${dir.path}/${AppConstants.privateKeyFile}')
        .writeAsString(privateKey);
    if (publicKey != null) {
      await File('${dir.path}/${AppConstants.publicKeyFile}')
          .writeAsString(publicKey);
    }
    await File('${dir.path}/${AppConstants.configJsonFile}')
        .writeAsString(jsonEncode(config));

    AppLogger.info('Saved rack configuration: $env-$rackName');
  }

  /// List all local racks
  Future<List<String>> listLocalRacks() async {
    final racksDir =
        Directory('${_configDir.path}/${AppConstants.racksDir}');
    if (!await racksDir.exists()) return [];

    final entities = await racksDir.list().toList();
    return entities
        .whereType<Directory>()
        .map((d) => d.path.split('/').last)
        .toList();
  }

  /// Delete rack configuration
  Future<void> deleteRackConfig(String env, String rackName) async {
    final dir = Directory(
      '${_configDir.path}/${AppConstants.racksDir}/$env-$rackName',
    );
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      AppLogger.info('Deleted rack configuration: $env-$rackName');
    }
  }

  // ============ AWS Profiles ============

  /// Get profile directory
  Directory getProfileDirectory(String profileName) {
    return Directory(
      '${_configDir.path}/${AppConstants.profilesDir}/$profileName',
    );
  }

  /// Save AWS profile
  Future<void> saveAwsProfile(
    String profileName,
    Map<String, dynamic> credentials,
  ) async {
    final dir = getProfileDirectory(profileName);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    await File('${dir.path}/credentials.json')
        .writeAsString(jsonEncode(credentials));
    AppLogger.info('Saved AWS profile: $profileName');
  }

  /// Load AWS profile
  Future<Map<String, dynamic>?> loadAwsProfile(String profileName) async {
    final file = File('${getProfileDirectory(profileName).path}/credentials.json');
    if (!await file.exists()) return null;

    final content = await file.readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// List all AWS profiles
  Future<List<String>> listAwsProfiles() async {
    final profilesDir =
        Directory('${_configDir.path}/${AppConstants.profilesDir}');
    if (!await profilesDir.exists()) return [];

    final entities = await profilesDir.list().toList();
    return entities
        .whereType<Directory>()
        .map((d) => d.path.split('/').last)
        .toList();
  }

  /// Delete AWS profile
  Future<void> deleteAwsProfile(String profileName) async {
    final dir = getProfileDirectory(profileName);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      AppLogger.info('Deleted AWS profile: $profileName');
    }

    // If deleting the active profile, clear the active profile setting
    final activeProfile = getActiveAwsProfile();
    if (activeProfile == profileName) {
      await clearActiveAwsProfile();
    }
  }

  // ============ Active AWS Profile ============

  /// Get the active AWS profile name
  String? getActiveAwsProfile() {
    return getSetting<String>('activeAwsProfile');
  }

  /// Set the active AWS profile
  Future<void> setActiveAwsProfile(String profileName) async {
    await saveSetting('activeAwsProfile', profileName);
    AppLogger.info('Set active AWS profile: $profileName');
  }

  /// Clear the active AWS profile
  Future<void> clearActiveAwsProfile() async {
    await deleteSetting('activeAwsProfile');
    AppLogger.info('Cleared active AWS profile');
  }

  /// Load the active AWS profile credentials
  Future<Map<String, dynamic>?> loadActiveAwsProfile() async {
    final activeProfile = getActiveAwsProfile();
    if (activeProfile == null) return null;
    return loadAwsProfile(activeProfile);
  }
}
