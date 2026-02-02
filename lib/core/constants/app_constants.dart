/// Application-wide constants
class AppConstants {
  AppConstants._();

  /// Application name
  static const String appName = 'Bikes Virtual Locks';

  /// Application version
  static const String appVersion = '1.0.0';

  /// Configuration directory name
  static const String configDirName = 'bikes-virtlocks';

  /// File names
  static const String settingsFile = 'settings.json';
  static const String caCertFile = 'ca.pem';

  /// Directory names
  static const String thingsDir = 'things';
  static const String racksDir = 'racks';
  static const String profilesDir = 'profiles';

  /// Certificate file names
  static const String certPemFile = 'cert.pem';
  static const String privateKeyFile = 'private.key';
  static const String publicKeyFile = 'public.key';
  static const String configJsonFile = 'config.json';

  /// Default values
  static const int defaultUnlockTimerMs = 5000;
  static const int defaultReconnectDelayMs = 5000;
  static const int maxReconnectDelayMs = 60000;

  /// Lock states
  static const int stateLocked = 1;
  static const int stateUnlocked = 0;
  static const int stateEmpty = 1;
  static const int stateOccupied = 0;
  static const int stateClampOk = 1;
  static const int stateClampError = 0;
}
