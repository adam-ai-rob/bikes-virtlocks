import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../providers/certificates_providers.dart';

/// Screen for managing certificates
class CertificatesScreen extends ConsumerStatefulWidget {
  const CertificatesScreen({super.key});

  @override
  ConsumerState<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends ConsumerState<CertificatesScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh certificates on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(certificatesProvider.notifier).loadCertificates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final certState = ref.watch(certificatesProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                Text(
                  'Certificate Management',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: certState.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      tooltip: 'Refresh',
                      onPressed: certState.isLoading
                          ? null
                          : () => ref
                              .read(certificatesProvider.notifier)
                              .loadCertificates(),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // CA Certificate status card
            _buildCaCertCard(certState),
            const SizedBox(height: 16),

            // Error display
            if (certState.error != null) ...[
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          certState.error!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            ref.read(certificatesProvider.notifier).clearError(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Section header with count
            Row(
              children: [
                Text(
                  'Local Certificates',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                if (certState.certificates.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${certState.certificates.length}',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Certificates list
            Expanded(
              child: _buildCertificatesList(certState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaCertCard(CertificatesState certState) {
    return Card(
      color: certState.hasCaCert ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              certState.hasCaCert ? Icons.verified_user : Icons.security,
              color: certState.hasCaCert
                  ? Colors.green.shade700
                  : Colors.orange.shade700,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Amazon Root CA Certificate',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    certState.hasCaCert
                        ? 'Installed. Required for MQTT connections to AWS IoT.'
                        : 'Not installed. Download required for MQTT connections.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (!certState.hasCaCert)
              FilledButton.icon(
                onPressed: certState.isLoading
                    ? null
                    : () async {
                        final success = await ref
                            .read(certificatesProvider.notifier)
                            .downloadCaCert();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(success
                                  ? 'CA certificate downloaded'
                                  : 'Failed to download CA certificate'),
                              backgroundColor:
                                  success ? Colors.green : Colors.red,
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Download'),
              )
            else
              const Icon(Icons.check_circle, color: Colors.green, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificatesList(CertificatesState certState) {
    if (certState.isLoading && certState.certificates.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading certificates...'),
          ],
        ),
      );
    }

    if (certState.certificates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No local certificates',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Certificates will appear here when you create things\nor import existing certificates',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade500,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: certState.certificates.length,
      itemBuilder: (context, index) {
        final cert = certState.certificates[index];
        return _CertificateCard(
          certificate: cert,
          onViewDetails: () => _showCertificateDetails(cert),
          onExport: () => _exportCertificate(cert),
          onDelete: () => _confirmDeleteCertificate(cert),
        );
      },
    );
  }

  void _showCertificateDetails(LocalCertificate cert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              cert.isComplete ? Icons.verified : Icons.warning_amber,
              color: cert.isComplete ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(cert.thingName)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(
                label: 'Environment',
                value: cert.environment ?? 'Unknown',
              ),
              _DetailRow(
                label: 'Type',
                value: cert.type ?? 'Unknown',
              ),
              _DetailRow(
                label: 'Certificate ID',
                value: cert.certificateId ?? 'N/A',
              ),
              _DetailRow(
                label: 'Created',
                value: cert.createdAt?.toLocal().toString() ?? 'Unknown',
              ),
              const Divider(),
              _DetailRow(
                label: 'Certificate File',
                value: cert.hasCertFile ? '✓ Present' : '✗ Missing',
                valueColor: cert.hasCertFile ? Colors.green : Colors.red,
              ),
              _DetailRow(
                label: 'Private Key File',
                value: cert.hasKeyFile ? '✓ Present' : '✗ Missing',
                valueColor: cert.hasKeyFile ? Colors.green : Colors.red,
              ),
              if (cert.certPath != null) ...[
                const Divider(),
                Text(
                  'Certificate Path:',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  cert.certPath!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCertificate(LocalCertificate cert) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select export directory',
    );

    if (result == null) return;

    final exportPath = await ref
        .read(certificatesProvider.notifier)
        .exportCertificates(cert.thingName, result);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exportPath != null
              ? 'Certificates exported to $exportPath'
              : 'Failed to export certificates'),
          backgroundColor: exportPath != null ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDeleteCertificate(LocalCertificate cert) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Certificate?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete the local certificates for "${cert.thingName}"?',
            ),
            const SizedBox(height: 8),
            const Text(
              'This will remove the certificate and private key files from local storage. '
              'The AWS IoT certificate will not be affected.',
              style: TextStyle(color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref
          .read(certificatesProvider.notifier)
          .deleteCertificate(cert.thingName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Deleted certificates for "${cert.thingName}"'
                : 'Failed to delete certificates'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }
}

class _CertificateCard extends StatelessWidget {
  final LocalCertificate certificate;
  final VoidCallback onViewDetails;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _CertificateCard({
    required this.certificate,
    required this.onViewDetails,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          certificate.isComplete ? Icons.verified : Icons.warning_amber,
          color: certificate.isComplete ? Colors.green : Colors.orange,
          size: 32,
        ),
        title: Text(certificate.thingName),
        subtitle: Row(
          children: [
            if (certificate.environment != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getEnvironmentColor(certificate.environment!)
                      .withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  certificate.environment!.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _getEnvironmentColor(certificate.environment!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (certificate.type != null) ...[
              Text(
                certificate.type!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              certificate.isComplete ? 'Complete' : 'Incomplete',
              style: TextStyle(
                fontSize: 12,
                color: certificate.isComplete ? Colors.green : Colors.orange,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Details',
              onPressed: onViewDetails,
            ),
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export',
              onPressed: certificate.isComplete ? onExport : null,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
          ],
        ),
        onTap: onViewDetails,
      ),
    );
  }

  Color _getEnvironmentColor(String env) {
    switch (env.toLowerCase()) {
      case 'dev':
        return Colors.blue;
      case 'test':
        return Colors.orange;
      case 'staging':
        return Colors.purple;
      case 'prod':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
