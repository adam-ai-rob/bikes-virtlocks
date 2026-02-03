/// AWS IoT related constants
class AwsConstants {
  AwsConstants._();

  /// Default AWS region
  static const String defaultRegion = 'eu-west-1';

  /// Default IoT endpoint (should be configured per account)
  static const String defaultIotEndpoint =
  'addt76a30qw7h-ats.iot.eu-west-1.amazonaws.com';
//      'alf2ft7d92jbb-ats.iot.eu-west-1.amazonaws.com';

  /// Thing types
  static const String thingTypeBikeLockDev = 'BikeLock-dev';
  static const String thingTypeBikeLockTest = 'BikeLock-test';
  static const String thingTypeBikeLockProd = 'BikeLock-prod';
  static const String thingTypeRackMasterDev = 'RackMaster-dev';
  static const String thingTypeRackMasterTest = 'RackMaster-test';
  static const String thingTypeRackMasterProd = 'RackMaster-prod';

  /// IoT policy name template
  static String iotPolicyName(String env) => '$env-hbr-api-bike-iot-policy';

  /// Thing name templates
  static String lockThingName(String env, String rackName, int index) {
    final paddedIndex = index.toString().padLeft(2, '0');
    return '$env-$rackName-LOCK$paddedIndex';
  }

  static String masterThingName(String env, String rackName) {
    return '$env-$rackName-MASTER';
  }

  /// Shadow topics
  static String shadowUpdateTopic(String thingId) =>
      '\$aws/things/$thingId/shadow/update';

  static String shadowDeltaTopic(String thingId) =>
      '\$aws/things/$thingId/shadow/update/delta';

  static String shadowGetTopic(String thingId) =>
      '\$aws/things/$thingId/shadow/get';

  static String shadowGetAcceptedTopic(String thingId) =>
      '\$aws/things/$thingId/shadow/get/accepted';

  static String shadowGetRejectedTopic(String thingId) =>
      '\$aws/things/$thingId/shadow/get/rejected';

  /// Environment prefixes
  static const List<String> environments = ['dev', 'test', 'prod'];

  /// Device types
  static const String deviceTypeBike = 'bike';
  static const String deviceTypeScooter = 'scooter';
}
