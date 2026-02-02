import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../services/storage_service.dart';
import '../../aws_config/providers/aws_config_providers.dart';

/// Represents a local certificate
class LocalCertificate {
  final String thingName;
  final String? certPath;
  final String? keyPath;
  final String? certificateArn;
  final String? certificateId;
  final String? environment;
  final String? type;
  final DateTime? createdAt;
  final bool hasCertFile;
  final bool hasKeyFile;

  LocalCertificate({
    required this.thingName,
    this.certPath,
    this.keyPath,
    this.certificateArn,
    this.certificateId,
    this.environment,
    this.type,
    this.createdAt,
    this.hasCertFile = false,
    this.hasKeyFile = false,
  });

  bool get isComplete => hasCertFile && hasKeyFile;
}

/// State for certificates management
class CertificatesState {
  final List<LocalCertificate> certificates;
  final bool isLoading;
  final String? error;
  final bool hasCaCert;

  const CertificatesState({
    this.certificates = const [],
    this.isLoading = false,
    this.error,
    this.hasCaCert = false,
  });

  CertificatesState copyWith({
    List<LocalCertificate>? certificates,
    bool? isLoading,
    String? error,
    bool? hasCaCert,
    bool clearError = false,
  }) {
    return CertificatesState(
      certificates: certificates ?? this.certificates,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error,
      hasCaCert: hasCaCert ?? this.hasCaCert,
    );
  }
}

/// Notifier for managing certificates state
class CertificatesNotifier extends StateNotifier<CertificatesState> {
  final Ref _ref;

  CertificatesNotifier(this._ref) : super(const CertificatesState()) {
    loadCertificates();
  }

  /// Load local certificates
  Future<void> loadCertificates() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final storage = StorageService.instance;

      // Check CA certificate
      final hasCaCert = await storage.caCertExists();

      // List local things
      final thingNames = await storage.listLocalThings();
      final certificates = <LocalCertificate>[];

      for (final thingName in thingNames) {
        final config = await storage.loadThingConfig(thingName);
        final certPath = storage.getThingCertPath(thingName);
        final keyPath = storage.getThingKeyPath(thingName);

        bool hasCertFile = false;
        bool hasKeyFile = false;

        if (certPath != null) {
          hasCertFile = await File(certPath).exists();
        }
        if (keyPath != null) {
          hasKeyFile = await File(keyPath).exists();
        }

        DateTime? createdAt;
        if (config != null && config['createdAt'] != null) {
          try {
            createdAt = DateTime.parse(config['createdAt'] as String);
          } catch (_) {}
        }

        certificates.add(LocalCertificate(
          thingName: thingName,
          certPath: certPath,
          keyPath: keyPath,
          certificateArn: config?['certificateArn'] as String?,
          certificateId: config?['certificateId'] as String?,
          environment: config?['environment'] as String?,
          type: config?['type'] as String?,
          createdAt: createdAt,
          hasCertFile: hasCertFile,
          hasKeyFile: hasKeyFile,
        ));
      }

      // Sort by thing name
      certificates.sort((a, b) => a.thingName.compareTo(b.thingName));

      state = state.copyWith(
        certificates: certificates,
        hasCaCert: hasCaCert,
        isLoading: false,
      );

      AppLogger.info(
          'Loaded ${certificates.length} local certificates, CA: $hasCaCert');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load certificates', e, stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Download the CA certificate
  Future<bool> downloadCaCert() async {
    try {
      final success =
          await _ref.read(awsConfigProvider.notifier).downloadCaCert();
      if (success) {
        state = state.copyWith(hasCaCert: true);
      }
      return success;
    } catch (e) {
      AppLogger.error('Failed to download CA cert', e);
      return false;
    }
  }

  /// Delete a certificate
  Future<bool> deleteCertificate(String thingName) async {
    try {
      await StorageService.instance.deleteThingCertificates(thingName);
      await loadCertificates();
      AppLogger.info('Deleted certificates for $thingName');
      return true;
    } catch (e) {
      AppLogger.error('Failed to delete certificate', e);
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Export certificates to a directory
  Future<String?> exportCertificates(String thingName, String exportPath) async {
    try {
      final storage = StorageService.instance;
      final certPath = storage.getThingCertPath(thingName);
      final keyPath = storage.getThingKeyPath(thingName);

      if (certPath == null || keyPath == null) {
        throw Exception('Certificate files not found');
      }

      final certFile = File(certPath);
      final keyFile = File(keyPath);

      if (!await certFile.exists() || !await keyFile.exists()) {
        throw Exception('Certificate files do not exist');
      }

      // Create export directory
      final exportDir = Directory(exportPath);
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      // Copy files
      await certFile.copy('$exportPath/${thingName}_cert.pem');
      await keyFile.copy('$exportPath/${thingName}_key.pem');

      AppLogger.info('Exported certificates for $thingName to $exportPath');
      return exportPath;
    } catch (e) {
      AppLogger.error('Failed to export certificates', e);
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Import certificates from files
  Future<bool> importCertificates({
    required String thingName,
    required String certFilePath,
    required String keyFilePath,
  }) async {
    try {
      final certFile = File(certFilePath);
      final keyFile = File(keyFilePath);

      if (!await certFile.exists()) {
        throw Exception('Certificate file not found: $certFilePath');
      }
      if (!await keyFile.exists()) {
        throw Exception('Private key file not found: $keyFilePath');
      }

      final certContent = await certFile.readAsString();
      final keyContent = await keyFile.readAsString();

      await StorageService.instance.saveThingCertificates(
        thingName,
        certificatePem: certContent,
        privateKey: keyContent,
      );

      await loadCertificates();
      AppLogger.info('Imported certificates for $thingName');
      return true;
    } catch (e) {
      AppLogger.error('Failed to import certificates', e);
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Clear the error
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// Provider for certificates management
final certificatesProvider =
    StateNotifierProvider<CertificatesNotifier, CertificatesState>((ref) {
  return CertificatesNotifier(ref);
});
