import 'package:flutter/material.dart' hide LockState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../aws_config/providers/aws_config_providers.dart';
import '../../domain/entities/lock_state.dart';
import '../../providers/locks_providers.dart';
import '../widgets/lock_card.dart';

/// Main screen for managing virtual locks
class LocksScreen extends ConsumerStatefulWidget {
  const LocksScreen({super.key});

  @override
  ConsumerState<LocksScreen> createState() => _LocksScreenState();
}

class _LocksScreenState extends ConsumerState<LocksScreen> {
  @override
  void initState() {
    super.initState();
    // Load locks on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locksProvider.notifier).loadLocks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final awsConfig = ref.watch(awsConfigProvider);
    final locksState = ref.watch(locksProvider);
    final filteredLocks = locksState.filteredLocks;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 32,
              ),
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
                        'Virtual Locks',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Connection status indicator
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: locksState.isConnected
                                  ? Colors.green.shade100
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  locksState.isConnected
                                      ? Icons.cloud_done
                                      : Icons.cloud_off,
                                  size: 16,
                                  color: locksState.isConnected
                                      ? Colors.green.shade700
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(locksState.isConnected
                                    ? 'Connected'
                                    : 'Disconnected'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton.icon(
                            onPressed: awsConfig.hasActiveProfile &&
                                    locksState.locks.isNotEmpty &&
                                    !locksState.isConnecting
                                ? () async {
                                    if (locksState.isConnected) {
                                      ref.read(locksProvider.notifier).disconnect();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Disconnected from AWS IoT'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    } else {
                                      final success = await ref
                                          .read(locksProvider.notifier)
                                          .connect();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(success
                                                ? 'Connected to AWS IoT'
                                                : 'Failed to connect - check logs'),
                                            backgroundColor:
                                                success ? Colors.green : Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  }
                                : null,
                            icon: locksState.isConnecting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(locksState.isConnected
                                    ? Icons.power_off
                                    : Icons.power_settings_new),
                            label: Text(locksState.isConnecting
                                ? 'Connecting...'
                                : locksState.isConnected
                                    ? 'Disconnect'
                                    : 'Connect'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Info card when not configured
                  if (!awsConfig.hasActiveProfile) ...[
                    Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber,
                                color: Colors.orange.shade700),
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
                                    'Go to "AWS Config" to configure your credentials and "Things" to create virtual locks.',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ] else if (locksState.locks.isEmpty &&
                      !locksState.isConnecting) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  'Getting Started',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '1. Go to "Things" to create or import virtual locks\n'
                              '2. Virtual locks need certificates stored locally\n'
                              '3. Once created, they will appear here automatically\n'
                              '4. Click "Connect" to start MQTT connection',
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  ref.read(locksProvider.notifier).loadLocks(),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Refresh Locks'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Simulation Mode Selector
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.settings_input_antenna, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            'Simulation Mode:',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(width: 12),
                          SegmentedButton<SimulationMode>(
                            segments: const [
                              ButtonSegment(
                                value: SimulationMode.masterRack,
                                label: Text('Master Rack'),
                                icon: Icon(Icons.hub),
                              ),
                              ButtonSegment(
                                value: SimulationMode.individualLock,
                                label: Text('Individual Lock'),
                                icon: Icon(Icons.lock),
                              ),
                            ],
                            selected: {locksState.simulationMode},
                            onSelectionChanged: locksState.isConnected
                                ? null
                                : (Set<SimulationMode> selected) {
                                    ref
                                        .read(locksProvider.notifier)
                                        .setSimulationMode(selected.first);
                                  },
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              locksState.simulationMode == SimulationMode.masterRack
                                  ? 'One connection per rack using master device'
                                  : 'Each lock connects independently',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                            ),
                          ),
                          if (locksState.isConnected)
                            Text(
                              locksState.connectionInfo,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Toolbar
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: Text('All (${locksState.locks.length})'),
                        selected: locksState.filter == LockFilter.all,
                        onSelected: (_) => ref
                            .read(locksProvider.notifier)
                            .setFilter(LockFilter.all),
                      ),
                      FilterChip(
                        label: Text('Connected (${locksState.connectedCount})'),
                        selected: locksState.filter == LockFilter.connected,
                        onSelected: (_) => ref
                            .read(locksProvider.notifier)
                            .setFilter(LockFilter.connected),
                      ),
                      FilterChip(
                        label: Text(
                            'Disconnected (${locksState.disconnectedCount})'),
                        selected: locksState.filter == LockFilter.disconnected,
                        onSelected: (_) => ref
                            .read(locksProvider.notifier)
                            .setFilter(LockFilter.disconnected),
                      ),
                      const SizedBox(width: 16),
                      if (locksState.selectedLocks.isNotEmpty) ...[
                        Text('${locksState.selectedLocks.length} selected'),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () =>
                              ref.read(locksProvider.notifier).clearSelection(),
                          child: const Text('Clear'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              ref.read(locksProvider.notifier).bulkToggleEmpty(),
                          icon: const Icon(Icons.sync_alt, size: 18),
                          label: const Text('Toggle Empty'),
                        ),
                      ] else ...[
                        TextButton(
                          onPressed: () =>
                              ref.read(locksProvider.notifier).selectAll(),
                          child: const Text('Select All'),
                        ),
                      ],
                      IconButton(
                        icon: locksState.isConnecting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                        onPressed: locksState.isConnecting
                            ? null
                            : () =>
                                ref.read(locksProvider.notifier).loadLocks(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Error display
                  if (locksState.error != null) ...[
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.red.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                locksState.error!,
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  ref.read(locksProvider.notifier).clearError(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Locks grid
                  _buildLocksGrid(context, filteredLocks, locksState),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLocksGrid(
    BuildContext context,
    List<LockState> locks,
    LocksState state,
  ) {
    if (state.isConnecting && locks.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading virtual locks...'),
            ],
          ),
        ),
      );
    }

    if (locks.isEmpty) {
      return SizedBox(
        height: 250,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                state.locks.isEmpty
                    ? 'No virtual locks configured'
                    : 'No locks match the current filter',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                state.locks.isEmpty
                    ? 'Create virtual locks in the "Things" tab'
                    : 'Try adjusting your filters',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate number of columns based on available width
        const minCardWidth = 280.0;
        final columns = (constraints.maxWidth / minCardWidth).floor().clamp(1, 4);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 1.1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: locks.length,
          itemBuilder: (context, index) {
            final lock = locks[index];
            return LockCard(
              lock: lock,
              isSelected: state.selectedLocks.contains(lock.thingId),
              onToggleEmpty: () =>
                  ref.read(locksProvider.notifier).toggleEmpty(lock.thingId),
              onToggleClamps: () =>
                  ref.read(locksProvider.notifier).toggleClamps(lock.thingId),
              onSelect: () =>
                  ref.read(locksProvider.notifier).toggleSelection(lock.thingId),
              onTap: () => _showLockDetails(context, lock),
            );
          },
        );
      },
    );
  }

  void _showLockDetails(BuildContext context, LockState lock) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              lock.isLocked ? Icons.lock : Icons.lock_open,
              color: lock.isLocked ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(lock.thingId)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Thing Name', value: lock.thingId),
              const Divider(),
              _DetailRow(label: 'Connected', value: lock.connected ? 'Yes' : 'No'),
              _DetailRow(label: 'Locked', value: lock.isLocked ? 'Yes' : 'No'),
              _DetailRow(label: 'Empty', value: lock.isEmpty ? 'Yes' : 'No'),
              _DetailRow(
                  label: 'Clamps', value: lock.areClampsOk ? 'OK' : 'Error'),
              _DetailRow(
                label: 'Timer',
                value: lock.hasActiveTimer
                    ? '${(lock.timer! / 1000).ceil()} seconds'
                    : 'Inactive',
              ),
              if (lock.lastUpdate != null)
                _DetailRow(
                  label: 'Last Update',
                  value: lock.lastUpdate!.toIso8601String().split('T').join(' '),
                ),
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
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
