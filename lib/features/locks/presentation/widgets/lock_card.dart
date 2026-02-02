import 'package:flutter/material.dart' hide LockState;

import '../../domain/entities/lock_state.dart';

/// Widget displaying a virtual lock card with state controls
class LockCard extends StatelessWidget {
  final LockState lock;
  final bool isSelected;
  final VoidCallback? onToggleEmpty;
  final VoidCallback? onToggleClamps;
  final VoidCallback? onSelect;
  final VoidCallback? onTap;

  const LockCard({
    super.key,
    required this.lock,
    this.isSelected = false,
    this.onToggleEmpty,
    this.onToggleClamps,
    this.onSelect,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              // Header row
              Row(
                children: [
                  // Lock icon with state color
                  _buildLockIcon(),
                  const SizedBox(width: 8),
                  // Thing ID
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getShortName(),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        _buildConnectionBadge(),
                      ],
                    ),
                  ),
                  // Selection checkbox
                  if (onSelect != null)
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => onSelect?.call(),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // State indicators row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStateIndicator(
                    icon: lock.isLocked ? Icons.lock : Icons.lock_open,
                    label: lock.isLocked ? 'Locked' : 'Unlocked',
                    color: lock.isLocked ? Colors.red : Colors.green,
                  ),
                  _buildStateIndicator(
                    icon: lock.isEmpty ? Icons.no_transfer : Icons.pedal_bike,
                    label: lock.isEmpty ? 'Empty' : 'Occupied',
                    color: lock.isEmpty ? Colors.orange : Colors.blue,
                  ),
                  _buildStateIndicator(
                    icon: lock.areClampsOk ? Icons.check_circle : Icons.error,
                    label: lock.areClampsOk ? 'Clamps OK' : 'Clamp Error',
                    color: lock.areClampsOk ? Colors.green : Colors.red,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Timer display (if active)
              if (lock.hasActiveTimer) ...[
                _buildTimerDisplay(context),
                const SizedBox(height: 12),
              ],

              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(
                    icon: lock.isEmpty ? Icons.pedal_bike : Icons.no_transfer,
                    label: lock.isEmpty ? 'Return Bike' : 'Take Bike',
                    // Only allow take/return when unlocked
                    onPressed: lock.isLocked ? null : onToggleEmpty,
                    color: lock.isLocked
                        ? Colors.grey
                        : (lock.isEmpty ? Colors.blue : Colors.orange),
                  ),
                  _buildControlButton(
                    icon: lock.areClampsOk ? Icons.error_outline : Icons.check,
                    label: lock.areClampsOk ? 'Fail Clamps' : 'Fix Clamps',
                    onPressed: onToggleClamps,
                    color: lock.areClampsOk ? Colors.grey : Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLockIcon() {
    Color backgroundColor;
    Color iconColor;
    IconData icon;

    if (lock.isEmpty) {
      backgroundColor = Colors.orange.shade100;
      iconColor = Colors.orange.shade700;
      icon = Icons.lock_outline;
    } else if (lock.isLocked) {
      backgroundColor = Colors.red.shade100;
      iconColor = Colors.red.shade700;
      icon = Icons.lock;
    } else {
      backgroundColor = Colors.green.shade100;
      iconColor = Colors.green.shade700;
      icon = Icons.lock_open;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: iconColor, size: 24),
    );
  }

  Widget _buildConnectionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: lock.connected ? Colors.green.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            lock.connected ? Icons.cloud_done : Icons.cloud_off,
            size: 10,
            color: lock.connected ? Colors.green.shade700 : Colors.grey.shade600,
          ),
          const SizedBox(width: 4),
          Text(
            lock.connected ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 10,
              color:
                  lock.connected ? Colors.green.shade700 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateIndicator({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: color),
        ),
      ],
    );
  }

  Widget _buildTimerDisplay(BuildContext context) {
    final seconds = (lock.timer! / 1000).ceil();
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    final timerText = '$minutes:${secs.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer, color: Colors.amber.shade700, size: 16),
          const SizedBox(width: 8),
          Text(
            'Auto-lock in $timerText',
            style: TextStyle(
              color: Colors.amber.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  String _getShortName() {
    // Try to get a shorter display name from the full thing ID
    final parts = lock.thingId.split('-');
    if (parts.length >= 3) {
      // e.g., "dev-rack1-bike1" -> "bike1"
      return parts.last;
    }
    return lock.thingId;
  }
}
