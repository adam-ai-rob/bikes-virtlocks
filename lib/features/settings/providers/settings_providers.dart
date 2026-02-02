import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../services/storage_service.dart';

/// Application settings state
class AppSettings {
  final String defaultEnvironment;
  final bool autoConnect;
  final bool debugMode;
  final ThemeMode themeMode;
  final int defaultUnlockTimerMs;

  const AppSettings({
    this.defaultEnvironment = 'dev',
    this.autoConnect = false,
    this.debugMode = false,
    this.themeMode = ThemeMode.system,
    this.defaultUnlockTimerMs = 5000,
  });

  AppSettings copyWith({
    String? defaultEnvironment,
    bool? autoConnect,
    bool? debugMode,
    ThemeMode? themeMode,
    int? defaultUnlockTimerMs,
  }) {
    return AppSettings(
      defaultEnvironment: defaultEnvironment ?? this.defaultEnvironment,
      autoConnect: autoConnect ?? this.autoConnect,
      debugMode: debugMode ?? this.debugMode,
      themeMode: themeMode ?? this.themeMode,
      defaultUnlockTimerMs: defaultUnlockTimerMs ?? this.defaultUnlockTimerMs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'defaultEnvironment': defaultEnvironment,
      'autoConnect': autoConnect,
      'debugMode': debugMode,
      'themeMode': themeMode.index,
      'defaultUnlockTimerMs': defaultUnlockTimerMs,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      defaultEnvironment: json['defaultEnvironment'] as String? ?? 'dev',
      autoConnect: json['autoConnect'] as bool? ?? false,
      debugMode: json['debugMode'] as bool? ?? false,
      themeMode: ThemeMode.values[json['themeMode'] as int? ?? 0],
      defaultUnlockTimerMs: json['defaultUnlockTimerMs'] as int? ?? 5000,
    );
  }
}

/// Notifier for managing application settings
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings =
          StorageService.instance.getSetting<Map<dynamic, dynamic>>('appSettings');
      if (settings != null) {
        final typedSettings = settings.map((k, v) => MapEntry(k.toString(), v));
        state = AppSettings.fromJson(typedSettings);
        AppLogger.info('Loaded app settings');
      }
    } catch (e) {
      AppLogger.error('Failed to load settings', e);
    }
  }

  Future<void> _saveSettings() async {
    try {
      await StorageService.instance.saveSetting('appSettings', state.toJson());
      AppLogger.debug('Saved app settings');
    } catch (e) {
      AppLogger.error('Failed to save settings', e);
    }
  }

  void setDefaultEnvironment(String environment) {
    state = state.copyWith(defaultEnvironment: environment);
    _saveSettings();
  }

  void setAutoConnect(bool autoConnect) {
    state = state.copyWith(autoConnect: autoConnect);
    _saveSettings();
  }

  void setDebugMode(bool debugMode) {
    state = state.copyWith(debugMode: debugMode);
    _saveSettings();
  }

  void setThemeMode(ThemeMode themeMode) {
    state = state.copyWith(themeMode: themeMode);
    _saveSettings();
  }

  void setDefaultUnlockTimer(int timerMs) {
    state = state.copyWith(defaultUnlockTimerMs: timerMs);
    _saveSettings();
  }

  /// Open the configuration directory in the file manager
  Future<bool> openConfigDirectory() async {
    try {
      final configDir = StorageService.instance.configDir;

      if (Platform.isMacOS) {
        await Process.run('open', [configDir.path]);
        return true;
      } else if (Platform.isWindows) {
        await Process.run('explorer', [configDir.path]);
        return true;
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [configDir.path]);
        return true;
      }

      AppLogger.warning('Unsupported platform for opening directory');
      return false;
    } catch (e) {
      AppLogger.error('Failed to open config directory', e);
      return false;
    }
  }

  /// Get the configuration directory path
  String get configDirectoryPath => StorageService.instance.configDir.path;

  /// Clear all local data
  Future<bool> clearAllData() async {
    try {
      final configDir = StorageService.instance.configDir;

      // Delete the config directory contents
      if (await configDir.exists()) {
        await for (final entity in configDir.list()) {
          await entity.delete(recursive: true);
        }
      }

      // Reset to default settings
      state = const AppSettings();

      AppLogger.info('Cleared all local data');
      return true;
    } catch (e) {
      AppLogger.error('Failed to clear local data', e);
      return false;
    }
  }
}

/// Provider for application settings
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

/// Convenience provider for theme mode
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(settingsProvider).themeMode;
});

/// Convenience provider for debug mode
final debugModeProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).debugMode;
});

/// Convenience provider for default environment
final defaultEnvironmentProvider = Provider<String>((ref) {
  return ref.watch(settingsProvider).defaultEnvironment;
});

/// Convenience provider for auto-connect setting
final autoConnectProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).autoConnect;
});
