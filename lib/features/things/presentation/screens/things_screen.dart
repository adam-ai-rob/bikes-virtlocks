import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../aws_config/providers/aws_config_providers.dart';
import '../../providers/things_providers.dart';

/// Screen for managing AWS IoT Things
class ThingsScreen extends ConsumerStatefulWidget {
  const ThingsScreen({super.key});

  @override
  ConsumerState<ThingsScreen> createState() => _ThingsScreenState();
}

class _ThingsScreenState extends ConsumerState<ThingsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final awsConfig = ref.watch(awsConfigProvider);
    final thingsState = ref.watch(thingsProvider);
    final filteredThings = thingsState.filteredThings;

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
                  'Thing Management',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: awsConfig.hasActiveProfile
                          ? () => _showCreateThingDialog(context)
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Create Thing'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: awsConfig.hasActiveProfile
                          ? () => _showCreateRackDialog(context)
                          : null,
                      icon: const Icon(Icons.grid_view),
                      label: const Text('Create Rack'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: awsConfig.hasActiveProfile
                          ? () => _showDeleteRackDialog(context)
                          : null,
                      icon: const Icon(Icons.delete_sweep),
                      label: const Text('Delete Rack'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // AWS not configured warning
            if (!awsConfig.hasActiveProfile) ...[
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange.shade700),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AWS Not Configured',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Please configure AWS credentials in the "AWS Config" tab to view and manage things.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Filters
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Search box
                SizedBox(
                  width: 250,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search things...',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _updateSearch('');
                              },
                            )
                          : null,
                    ),
                    onChanged: _updateSearch,
                  ),
                ),

                // Environment filter
                DropdownButton<String>(
                  value: thingsState.filter.environment ?? 'all',
                  items: [
                    const DropdownMenuItem(
                        value: 'all', child: Text('All Environments')),
                    ...thingsState.availableEnvironments.map(
                      (env) => DropdownMenuItem(
                        value: env,
                        child: Text(env.toUpperCase()),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    ref.read(thingsProvider.notifier).updateFilter(
                          thingsState.filter.copyWith(
                            environment: value == 'all' ? null : value,
                            clearEnvironment: value == 'all',
                          ),
                        );
                  },
                ),

                // Type filter
                DropdownButton<String>(
                  value: thingsState.filter.deviceType ?? 'all',
                  items: [
                    const DropdownMenuItem(
                        value: 'all', child: Text('All Types')),
                    ...thingsState.availableDeviceTypes.map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(
                            type[0].toUpperCase() + type.substring(1) + 's'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    ref.read(thingsProvider.notifier).updateFilter(
                          thingsState.filter.copyWith(
                            deviceType: value == 'all' ? null : value,
                            clearDeviceType: value == 'all',
                          ),
                        );
                  },
                ),

                // Local certificates filter
                FilterChip(
                  label: const Text('Has Certificates'),
                  selected: thingsState.filter.showOnlyWithCertificates,
                  onSelected: (selected) {
                    ref.read(thingsProvider.notifier).updateFilter(
                          thingsState.filter
                              .copyWith(showOnlyWithCertificates: selected),
                        );
                  },
                ),

                // Stats
                if (thingsState.things.isNotEmpty)
                  Text(
                    '${filteredThings.length} of ${thingsState.things.length} things',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),

                // Refresh button
                IconButton(
                  icon: thingsState.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  tooltip: 'Refresh from AWS',
                  onPressed: thingsState.isLoading || !awsConfig.hasActiveProfile
                      ? null
                      : () => ref.read(thingsProvider.notifier).loadThings(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Error message
            if (thingsState.error != null) ...[
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
                          thingsState.error!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            ref.read(thingsProvider.notifier).clearError(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Things list
            Expanded(
              child: _buildThingsList(context, filteredThings, thingsState),
            ),
          ],
        ),
      ),
    );
  }

  void _updateSearch(String query) {
    final filter = ref.read(thingsProvider).filter;
    ref.read(thingsProvider.notifier).updateFilter(
          filter.copyWith(
            searchQuery: query.isEmpty ? null : query,
            clearSearchQuery: query.isEmpty,
          ),
        );
  }

  Widget _buildThingsList(
    BuildContext context,
    List<ThingModel> things,
    ThingsState state,
  ) {
    if (state.isLoading && things.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading things from AWS...'),
          ],
        ),
      );
    }

    if (things.isEmpty) {
      final awsConfig = ref.read(awsConfigProvider);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              state.things.isEmpty ? 'No things found' : 'No things match filters',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              state.things.isEmpty
                  ? (awsConfig.hasActiveProfile
                      ? 'Click refresh to load things from AWS IoT'
                      : 'Configure AWS credentials first')
                  : 'Try adjusting your filters',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade500,
                  ),
            ),
            if (awsConfig.hasActiveProfile && state.things.isEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref.read(thingsProvider.notifier).loadThings(),
                icon: const Icon(Icons.refresh),
                label: const Text('Load Things'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: things.length,
      itemBuilder: (context, index) {
        final thing = things[index];
        return _ThingListTile(
          thing: thing,
          onTap: () => _showThingDetails(context, thing),
          onDelete: () => _confirmDeleteThing(context, thing),
        );
      },
    );
  }

  void _showThingDetails(BuildContext context, ThingModel thing) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              thing.isMaster ? Icons.hub : Icons.lock_outline,
              color: thing.hasLocalCertificates ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(thing.thingName)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailRow(label: 'ARN', value: thing.thingArn ?? 'N/A'),
                _DetailRow(
                    label: 'Environment', value: thing.environment ?? 'Unknown'),
                _DetailRow(
                    label: 'Device Type', value: thing.deviceType ?? 'Unknown'),
                _DetailRow(label: 'Thing Type', value: thing.thingTypeName ?? 'N/A'),
                _DetailRow(label: 'Lobby', value: thing.lobby ?? 'N/A'),
                _DetailRow(
                    label: 'Enabled', value: thing.isEnabled ? 'Yes' : 'No'),
                _DetailRow(
                  label: 'Local Certificates',
                  value: thing.hasLocalCertificates ? 'Available' : 'Not found',
                  valueColor:
                      thing.hasLocalCertificates ? Colors.green : Colors.orange,
                ),
                if (thing.attributes.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    'Attributes',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ...thing.attributes.entries.map(
                    (e) => _DetailRow(label: e.key, value: e.value),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (!thing.hasLocalCertificates)
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _downloadThingCertificate(context, thing.thingName);
              },
              icon: const Icon(Icons.download),
              label: const Text('Download Cert'),
            ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _importPrivateKey(thing.thingName);
            },
            icon: const Icon(Icons.key),
            label: const Text('Import Key'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showEditThingDialog(context, thing);
            },
            icon: const Icon(Icons.edit),
            label: const Text('Edit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadThingCertificate(BuildContext context, String thingName) async {
    // Get navigator before async operation
    final navigator = Navigator.of(context);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Downloading certificate...'),
          ],
        ),
      ),
    );

    final result = await ref.read(thingsProvider.notifier).downloadThingCertificate(thingName);

    // Close loading dialog using stored navigator
    if (mounted) navigator.pop();

    if (result != null) {
      // Show success dialog with certificate info
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Certificate Downloaded'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(label: 'Thing', value: result.thingName),
                  _DetailRow(label: 'Certificate ID', value: result.certificateId),
                  _DetailRow(label: 'Status', value: result.status),
                  const Divider(),
                  Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange.shade700),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Private Key Required',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'AWS IoT does not allow downloading private keys after creation. '
                                  'You must provide the private key separately to use this certificate for device simulation.',
                                  style: TextStyle(fontSize: 12),
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } else {
      // Show error
      if (mounted) {
        final error = ref.read(thingsProvider).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error ?? 'Failed to download certificate'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importPrivateKey(String thingName) async {
    // Save scaffold messenger before async operation
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Pick a private key file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      dialogTitle: 'Select Private Key File for $thingName',
    );

    if (result == null || result.files.isEmpty) {
      return; // User cancelled
    }

    final filePath = result.files.single.path;
    if (filePath == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Could not access selected file'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Import the private key
    final success = await ref.read(thingsProvider.notifier).importPrivateKey(thingName, filePath);

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Private key imported for "$thingName"'
            : ref.read(thingsProvider).error ?? 'Failed to import private key'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  void _showEditThingDialog(BuildContext context, ThingModel thing) {
    final enabledController = TextEditingController(
      text: thing.attributes['enabled'] ?? 'true',
    );
    final lobbyController = TextEditingController(
      text: thing.attributes['lobby'] ?? '',
    );
    final typeController = TextEditingController(
      text: thing.attributes['type'] ?? thing.deviceType ?? '',
    );
    bool isEnabled = thing.isEnabled;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.edit),
              const SizedBox(width: 8),
              Expanded(child: Text('Edit ${thing.thingName}')),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Enabled'),
                  subtitle: const Text('Whether this device is active'),
                  value: isEnabled,
                  onChanged: (value) {
                    setDialogState(() => isEnabled = value);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: typeController,
                  decoration: const InputDecoration(
                    labelText: 'Device Type',
                    hintText: 'e.g., bike, scooter, master',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: lobbyController,
                  decoration: const InputDecoration(
                    labelText: 'Lobby / Location',
                    hintText: 'e.g., Building A Lobby',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);

                final attributes = <String, String>{
                  'enabled': isEnabled.toString(),
                  'type': typeController.text,
                };
                if (lobbyController.text.isNotEmpty) {
                  attributes['lobby'] = lobbyController.text;
                }

                final success = await ref
                    .read(thingsProvider.notifier)
                    .updateThingAttributes(
                      thingName: thing.thingName,
                      attributes: attributes,
                    );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? 'Updated "${thing.thingName}"'
                          : 'Failed to update thing'),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteThing(BuildContext context, ThingModel thing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Thing?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${thing.thingName}"?'),
            const SizedBox(height: 8),
            const Text(
              'This will also delete associated certificates from AWS and local storage.',
              style: TextStyle(color: Colors.red),
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
      final success =
          await ref.read(thingsProvider.notifier).deleteThing(thing.thingName);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${thing.thingName}"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _showCreateThingDialog(BuildContext context) {
    final nameController = TextEditingController();
    String environment = 'dev';
    String deviceType = 'bike';
    final lobbyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create New Thing'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Thing Name',
                    hintText: 'e.g., dev-rack1-bike1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: environment,
                        decoration: const InputDecoration(
                          labelText: 'Environment',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'dev', child: Text('Development')),
                          DropdownMenuItem(value: 'test', child: Text('Test')),
                          DropdownMenuItem(value: 'staging', child: Text('Staging')),
                          DropdownMenuItem(value: 'prod', child: Text('Production')),
                        ],
                        onChanged: (value) {
                          setDialogState(() => environment = value!);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: deviceType,
                        decoration: const InputDecoration(
                          labelText: 'Device Type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'bike', child: Text('Bike')),
                          DropdownMenuItem(value: 'scooter', child: Text('Scooter')),
                          DropdownMenuItem(value: 'master', child: Text('Master')),
                        ],
                        onChanged: (value) {
                          setDialogState(() => deviceType = value!);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: lobbyController,
                  decoration: const InputDecoration(
                    labelText: 'Lobby (optional)',
                    hintText: 'e.g., Building A Lobby',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameController.text.isEmpty) return;

                Navigator.pop(context);

                final attributes = <String, String>{
                  'type': deviceType,
                  'enabled': 'true',
                };
                if (lobbyController.text.isNotEmpty) {
                  attributes['lobby'] = lobbyController.text;
                }

                await ref.read(thingsProvider.notifier).createThing(
                      thingName: nameController.text,
                      environment: environment,
                      attributes: attributes,
                    );
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRackCreationResult(BuildContext context, RackCreationResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result.hasErrors ? Icons.warning_amber : Icons.check_circle,
              color: result.hasErrors ? Colors.orange : Colors.green,
            ),
            const SizedBox(width: 8),
            const Text('Rack Creation Complete'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Created ${result.successCount} things for rack "${result.rackName}" in ${result.environment}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Text(
                'Created Things:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: result.createdThings
                        .map((name) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  const Icon(Icons.check,
                                      color: Colors.green, size: 16),
                                  const SizedBox(width: 8),
                                  Text(name),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
              if (result.hasErrors) ...[
                const SizedBox(height: 16),
                Text(
                  'Errors:',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: Colors.red),
                ),
                const SizedBox(height: 8),
                ...result.errors.map((error) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error,
                              color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              error,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showDeleteRackDialog(BuildContext context) {
    final thingsState = ref.read(thingsProvider);
    final racks = ref.read(thingsProvider.notifier).getUniqueRacks();

    if (racks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No racks found'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String? selectedRack = racks.first;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Get things for selected rack
          List<ThingModel> rackThings = [];
          if (selectedRack != null) {
            final parts = selectedRack!.split('-');
            if (parts.length >= 2) {
              rackThings = ref
                  .read(thingsProvider.notifier)
                  .getRackThings(parts[0], parts[1]);
            }
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.delete_sweep, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete Rack'),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select a rack to delete. This will delete ALL things in the rack including the master and all locks.',
                    style: TextStyle(color: Colors.orange),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedRack,
                    decoration: const InputDecoration(
                      labelText: 'Select Rack',
                      border: OutlineInputBorder(),
                    ),
                    items: racks
                        .map((rack) => DropdownMenuItem(
                              value: rack,
                              child: Text(rack),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedRack = value);
                    },
                  ),
                  if (rackThings.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Things to be deleted (${rackThings.length}):',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 150),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: rackThings
                                      .map((t) => Text('• ${t.thingName}'))
                                      .toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: selectedRack == null || rackThings.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(context);

                        // Show confirmation
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Confirm Deletion'),
                            content: Text(
                              'Are you sure you want to delete rack "$selectedRack" '
                              'and all ${rackThings.length} things?\n\n'
                              'This action cannot be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );

                        if (confirmed == true && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Deleting rack...'),
                              duration: Duration(seconds: 30),
                            ),
                          );

                          final parts = selectedRack!.split('-');
                          final result = await ref
                              .read(thingsProvider.notifier)
                              .deleteRack(
                                environment: parts[0],
                                rackName: parts[1],
                              );

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).clearSnackBars();
                            _showRackDeletionResult(context, result);
                          }
                        }
                      },
                child: const Text('Delete Rack'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRackDeletionResult(BuildContext context, RackDeletionResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result.hasErrors ? Icons.warning_amber : Icons.check_circle,
              color: result.hasErrors ? Colors.orange : Colors.green,
            ),
            const SizedBox(width: 8),
            const Text('Rack Deletion Complete'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deleted ${result.successCount} things from rack "${result.rackName}"',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (result.hasErrors) ...[
                const SizedBox(height: 16),
                Text(
                  'Errors:',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: Colors.red),
                ),
                const SizedBox(height: 8),
                ...result.errors.map((error) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              error,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCreateRackDialog(BuildContext context) {
    final nameController = TextEditingController();
    String environment = 'dev';
    int bikeCount = 4;
    int scooterCount = 0;
    final lobbyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create New Rack'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Rack Name',
                    hintText: 'e.g., RACK07',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: environment,
                  decoration: const InputDecoration(
                    labelText: 'Environment',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'dev', child: Text('Development')),
                    DropdownMenuItem(value: 'test', child: Text('Test')),
                    DropdownMenuItem(value: 'staging', child: Text('Staging')),
                    DropdownMenuItem(value: 'prod', child: Text('Production')),
                  ],
                  onChanged: (value) {
                    setDialogState(() => environment = value!);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Bike Locks'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                onPressed: bikeCount > 0
                                    ? () => setDialogState(() => bikeCount--)
                                    : null,
                                icon: const Icon(Icons.remove),
                              ),
                              Text('$bikeCount',
                                  style: Theme.of(context).textTheme.titleLarge),
                              IconButton(
                                onPressed: () => setDialogState(() => bikeCount++),
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Scooter Locks'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                onPressed: scooterCount > 0
                                    ? () => setDialogState(() => scooterCount--)
                                    : null,
                                icon: const Icon(Icons.remove),
                              ),
                              Text('$scooterCount',
                                  style: Theme.of(context).textTheme.titleLarge),
                              IconButton(
                                onPressed: () =>
                                    setDialogState(() => scooterCount++),
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: lobbyController,
                  decoration: const InputDecoration(
                    labelText: 'Lobby (optional)',
                    hintText: 'e.g., Building A Lobby',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Preview',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text('This will create ${1 + bikeCount + scooterCount} things:'),
                        Text('  - 1 master: $environment-${nameController.text.isEmpty ? "RACK" : nameController.text}-master'),
                        if (bikeCount > 0)
                          Text('  - $bikeCount bikes: $environment-${nameController.text.isEmpty ? "RACK" : nameController.text}-bike1...$bikeCount'),
                        if (scooterCount > 0)
                          Text('  - $scooterCount scooters: $environment-${nameController.text.isEmpty ? "RACK" : nameController.text}-scooter1...$scooterCount'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameController.text.isEmpty) return;
                if (bikeCount == 0 && scooterCount == 0) return;

                Navigator.pop(context);

                // Show progress
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Creating rack...'),
                    duration: Duration(seconds: 30),
                  ),
                );

                final result = await ref.read(thingsProvider.notifier).createRack(
                      environment: environment,
                      rackName: nameController.text,
                      bikeLockCount: bikeCount,
                      scooterLockCount: scooterCount,
                      lobby: lobbyController.text.isNotEmpty
                          ? lobbyController.text
                          : null,
                    );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).clearSnackBars();

                  if (result != null) {
                    _showRackCreationResult(context, result);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to create rack'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Create Rack'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThingListTile extends StatelessWidget {
  final ThingModel thing;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ThingListTile({
    required this.thing,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          thing.isMaster ? Icons.hub : Icons.lock_outline,
          color: thing.hasLocalCertificates ? Colors.green : Colors.grey,
          size: 32,
        ),
        title: Text(thing.thingName),
        subtitle: Row(
          children: [
            if (thing.environment != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getEnvironmentColor(thing.environment!).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  thing.environment!.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _getEnvironmentColor(thing.environment!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (thing.deviceType != null) ...[
              Text(
                thing.deviceType!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
            ],
            if (thing.hasLocalCertificates)
              const Icon(Icons.verified, size: 14, color: Colors.green),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Details',
              onPressed: onTap,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
          ],
        ),
        onTap: onTap,
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
