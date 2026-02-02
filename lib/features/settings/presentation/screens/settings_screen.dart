import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../providers/settings_providers.dart';

/// Application settings screen
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Settings',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),

            // General settings
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'General',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.developer_mode),
                    title: const Text('Default Environment'),
                    subtitle: const Text('Used when creating new things'),
                    trailing: DropdownButton<String>(
                      value: settings.defaultEnvironment,
                      items: const [
                        DropdownMenuItem(value: 'dev', child: Text('Development')),
                        DropdownMenuItem(value: 'test', child: Text('Test')),
                        DropdownMenuItem(value: 'staging', child: Text('Staging')),
                        DropdownMenuItem(value: 'prod', child: Text('Production')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          settingsNotifier.setDefaultEnvironment(value);
                        }
                      },
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.power),
                    title: const Text('Auto-connect on startup'),
                    subtitle:
                        const Text('Automatically connect to AWS IoT when app starts'),
                    value: settings.autoConnect,
                    onChanged: (value) {
                      settingsNotifier.setAutoConnect(value);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.bug_report),
                    title: const Text('Debug mode'),
                    subtitle: const Text('Show verbose logging and debug information'),
                    value: settings.debugMode,
                    onChanged: (value) {
                      settingsNotifier.setDebugMode(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Appearance
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.palette),
                    title: const Text('Theme'),
                    trailing: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                        ),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (selected) {
                        settingsNotifier.setThemeMode(selected.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Lock defaults
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Lock Defaults',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.timer),
                    title: const Text('Default unlock timer'),
                    subtitle: const Text('Time before lock automatically locks'),
                    trailing: DropdownButton<int>(
                      value: settings.defaultUnlockTimerMs,
                      items: const [
                        DropdownMenuItem(value: 3000, child: Text('3 seconds')),
                        DropdownMenuItem(value: 5000, child: Text('5 seconds')),
                        DropdownMenuItem(value: 10000, child: Text('10 seconds')),
                        DropdownMenuItem(value: 30000, child: Text('30 seconds')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          settingsNotifier.setDefaultUnlockTimer(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Storage
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Storage',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder),
                    title: const Text('Configuration Directory'),
                    subtitle: Text(settingsNotifier.configDirectoryPath),
                    trailing: TextButton.icon(
                      onPressed: () async {
                        final success = await settingsNotifier.openConfigDirectory();
                        if (context.mounted && !success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to open directory'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('Open'),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Clear Local Data'),
                    subtitle: const Text('Remove all cached data and settings'),
                    trailing: OutlinedButton(
                      onPressed: () => _showClearDataDialog(context, ref),
                      child: const Text('Clear'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // About
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'About',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text(AppConstants.appName),
                    subtitle: const Text('Version ${AppConstants.appVersion}'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.code),
                    title: const Text('Source'),
                    subtitle: const Text('bikes-virtlocks'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearDataDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Local Data?'),
        content: const Text(
          'This will remove all settings, AWS profiles, and cached data. '
          'Certificates stored locally will also be removed. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);

              final success =
                  await ref.read(settingsProvider.notifier).clearAllData();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'All local data cleared. Restart the app for changes to take effect.'
                          : 'Failed to clear data',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );
  }
}
