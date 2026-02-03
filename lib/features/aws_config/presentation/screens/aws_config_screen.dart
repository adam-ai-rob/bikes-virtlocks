import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../../services/storage_service.dart';
import '../../providers/aws_config_providers.dart';

/// Screen for configuring AWS credentials and profiles
class AwsConfigScreen extends ConsumerStatefulWidget {
  const AwsConfigScreen({super.key});

  @override
  ConsumerState<AwsConfigScreen> createState() => _AwsConfigScreenState();
}

class _AwsConfigScreenState extends ConsumerState<AwsConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _profileNameController = TextEditingController();
  final _regionController = TextEditingController(text: 'eu-west-1');
  final _endpointController = TextEditingController();
  final _policyNameController = TextEditingController();
  final _accessKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();

  bool _obscureSecretKey = true;
  bool _isSaving = false;
  List<String> _profiles = [];

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final profiles = await StorageService.instance.listAwsProfiles();
    setState(() {
      _profiles = profiles;
    });
    // Also refresh the provider state
    ref.read(awsConfigProvider.notifier).refreshProfiles();
  }

  @override
  void dispose() {
    _profileNameController.dispose();
    _regionController.dispose();
    _endpointController.dispose();
    _policyNameController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final profileName = _profileNameController.text.trim();
      final policyName = _policyNameController.text.trim();
      final credentials = {
        'region': _regionController.text.trim(),
        'endpoint': _endpointController.text.trim(),
        'policyName': policyName.isNotEmpty ? policyName : null,
        'accessKeyId': _accessKeyController.text.trim(),
        'secretAccessKey': _secretKeyController.text.trim(),
      };

      await StorageService.instance.saveAwsProfile(profileName, credentials);

      AppLogger.info('Saved AWS profile: $profileName');

      // Reload profiles list
      await _loadProfiles();

      // Clear form
      _profileNameController.clear();
      _endpointController.clear();
      _policyNameController.clear();
      _accessKeyController.clear();
      _secretKeyController.clear();
      _regionController.text = 'eu-west-1';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile "$profileName" saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to save profile', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteProfile(String profileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Profile?'),
        content: Text('Are you sure you want to delete "$profileName"?'),
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

    if (confirmed == true) {
      await StorageService.instance.deleteAwsProfile(profileName);
      await _loadProfiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile "$profileName" deleted'),
          ),
        );
      }
    }
  }

  Future<void> _loadProfileToForm(String profileName) async {
    final profile = await StorageService.instance.loadAwsProfile(profileName);
    if (profile != null) {
      setState(() {
        _profileNameController.text = profileName;
        _regionController.text = profile['region'] ?? 'eu-west-1';
        _endpointController.text = profile['endpoint'] ?? '';
        _policyNameController.text = profile['policyName'] ?? '';
        _accessKeyController.text = profile['accessKeyId'] ?? '';
        _secretKeyController.text = profile['secretAccessKey'] ?? '';
      });
    }
  }

  Future<void> _setActiveProfile(String profileName) async {
    try {
      await ref.read(awsConfigProvider.notifier).setActiveProfile(profileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Active profile set to "$profileName"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set active profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _discoverEndpoint() async {
    try {
      final endpoint =
          await ref.read(awsConfigProvider.notifier).discoverEndpoint();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Discovered endpoint: $endpoint'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to discover endpoint: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testConnection() async {
    final success =
        await ref.read(awsConfigProvider.notifier).testConnection();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Connection successful!'
              : 'Connection failed. Check your credentials.'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadCaCert() async {
    final success =
        await ref.read(awsConfigProvider.notifier).downloadCaCert();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'CA certificate downloaded successfully'
              : 'Failed to download CA certificate'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Widget _buildCaCertCard(AwsConfigState awsConfig) {
    return Card(
      color: awsConfig.hasCaCert ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              awsConfig.hasCaCert ? Icons.verified_user : Icons.warning_amber,
              color: awsConfig.hasCaCert
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
                    awsConfig.hasCaCert
                        ? 'CA certificate is installed. Required for MQTT connections.'
                        : 'CA certificate not found. Download it to enable MQTT connections.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (!awsConfig.hasCaCert)
              FilledButton.icon(
                onPressed: awsConfig.isConnecting ? null : _downloadCaCert,
                icon: awsConfig.isConnecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download, size: 18),
                label: Text(awsConfig.isConnecting ? 'Downloading...' : 'Download'),
              )
            else
              const Icon(Icons.check_circle, color: Colors.green, size: 28),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final awsConfig = ref.watch(awsConfigProvider);
    final activeProfile = awsConfig.activeProfileName;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'AWS Configuration',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Configure your AWS credentials to connect to AWS IoT Core. '
              'Credentials are stored locally and never sent anywhere except AWS.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 24),

            // Active profile card
            if (activeProfile != null) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Active Profile',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          if (awsConfig.isConnecting)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activeProfile,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Region: ${awsConfig.activeProfileCredentials?['region'] ?? 'N/A'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (awsConfig.hasEndpoint) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Endpoint: ${awsConfig.iotEndpoint}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                if (awsConfig.hasPolicyName) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'IoT Policy: ${awsConfig.iotPolicyName}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: awsConfig.isConnected
                                      ? Colors.green.shade100
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      awsConfig.isConnected
                                          ? Icons.cloud_done
                                          : Icons.cloud_off,
                                      size: 14,
                                      color: awsConfig.isConnected
                                          ? Colors.green.shade700
                                          : Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      awsConfig.isConnected
                                          ? 'Connected'
                                          : 'Not tested',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: awsConfig.isConnected
                                            ? Colors.green.shade700
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: awsConfig.isConnecting
                                ? null
                                : _discoverEndpoint,
                            icon: const Icon(Icons.search, size: 18),
                            label: const Text('Discover Endpoint'),
                          ),
                          FilledButton.icon(
                            onPressed:
                                awsConfig.isConnecting ? null : _testConnection,
                            icon: const Icon(Icons.wifi_tethering, size: 18),
                            label: const Text('Test Connection'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // CA Certificate section
            _buildCaCertCard(awsConfig),
            const SizedBox(height: 24),

            // Profiles section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saved Profiles',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    if (_profiles.isEmpty)
                      const Text('No profiles configured. Create one below.')
                    else
                      ..._profiles.map((profile) {
                        final isActive = profile == activeProfile;
                        return ListTile(
                          leading: Icon(
                            isActive
                                ? Icons.check_circle
                                : Icons.account_circle_outlined,
                            color: isActive ? Colors.green : null,
                          ),
                          title: Row(
                            children: [
                              Text(profile),
                              if (isActive) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isActive)
                                TextButton(
                                  onPressed: () => _setActiveProfile(profile),
                                  child: const Text('Set Active'),
                                ),
                              IconButton(
                                icon: const Icon(Icons.edit),
                                tooltip: 'Edit',
                                onPressed: () => _loadProfileToForm(profile),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete',
                                onPressed: () => _deleteProfile(profile),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // New profile form
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create / Edit Profile',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),

                      // Profile name
                      TextFormField(
                        controller: _profileNameController,
                        decoration: const InputDecoration(
                          labelText: 'Profile Name',
                          hintText: 'e.g., dev, production',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Profile name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Region
                      TextFormField(
                        controller: _regionController,
                        decoration: const InputDecoration(
                          labelText: 'AWS Region',
                          hintText: 'e.g., eu-west-1',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.public),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Region is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // IoT Endpoint
                      TextFormField(
                        controller: _endpointController,
                        decoration: const InputDecoration(
                          labelText: 'IoT Endpoint (optional)',
                          hintText: 'e.g., xxxxx-ats.iot.eu-west-1.amazonaws.com',
                          helperText:
                              'Leave empty to auto-discover after setting as active',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.link),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // IoT Policy Name
                      TextFormField(
                        controller: _policyNameController,
                        decoration: const InputDecoration(
                          labelText: 'IoT Policy Name (optional)',
                          hintText: 'e.g., dev-hbr-api-bike-iot-policy',
                          helperText:
                              'Policy to attach when creating new things. Leave empty for default.',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.policy),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Access Key ID
                      TextFormField(
                        controller: _accessKeyController,
                        decoration: const InputDecoration(
                          labelText: 'Access Key ID',
                          hintText: 'AKIAIOSFODNN7EXAMPLE',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.key),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Access Key ID is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Secret Access Key
                      TextFormField(
                        controller: _secretKeyController,
                        obscureText: _obscureSecretKey,
                        decoration: InputDecoration(
                          labelText: 'Secret Access Key',
                          hintText: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureSecretKey
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureSecretKey = !_obscureSecretKey;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Secret Access Key is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () {
                              _profileNameController.clear();
                              _regionController.text = 'eu-west-1';
                              _endpointController.clear();
                              _policyNameController.clear();
                              _accessKeyController.clear();
                              _secretKeyController.clear();
                            },
                            child: const Text('Clear'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _isSaving ? null : _saveProfile,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(_isSaving ? 'Saving...' : 'Save Profile'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Info card
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Security Note',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Your credentials are stored locally on your machine. '
                            'For production use, consider using IAM roles with minimal permissions.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
