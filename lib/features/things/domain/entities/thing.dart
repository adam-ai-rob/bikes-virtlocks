import 'package:equatable/equatable.dart';

/// Represents an AWS IoT Thing
class Thing extends Equatable {
  /// Thing name (e.g., dev-VirtualBikeLock01)
  final String thingName;

  /// Thing ARN
  final String? thingArn;

  /// Thing type name (e.g., BikeLock-dev)
  final String? thingTypeName;

  /// Thing attributes
  final ThingAttributes attributes;

  /// Certificate ARN if attached
  final String? certificateArn;

  const Thing({
    required this.thingName,
    this.thingArn,
    this.thingTypeName,
    this.attributes = const ThingAttributes(),
    this.certificateArn,
  });

  /// Extract environment from thing name (e.g., "dev" from "dev-VirtualBikeLock01")
  String get environment {
    final parts = thingName.split('-');
    if (parts.isNotEmpty) {
      final env = parts.first.toLowerCase();
      if (['dev', 'test', 'prod'].contains(env)) {
        return env;
      }
    }
    return 'dev';
  }

  /// Whether the thing is enabled
  bool get isEnabled => attributes.enabled == '1' || attributes.enabled == 'true';

  Thing copyWith({
    String? thingName,
    String? thingArn,
    String? thingTypeName,
    ThingAttributes? attributes,
    String? certificateArn,
  }) {
    return Thing(
      thingName: thingName ?? this.thingName,
      thingArn: thingArn ?? this.thingArn,
      thingTypeName: thingTypeName ?? this.thingTypeName,
      attributes: attributes ?? this.attributes,
      certificateArn: certificateArn ?? this.certificateArn,
    );
  }

  @override
  List<Object?> get props => [
        thingName,
        thingArn,
        thingTypeName,
        attributes,
        certificateArn,
      ];
}

/// Thing attributes
class ThingAttributes extends Equatable {
  /// Whether the thing is enabled ("0" or "1")
  final String enabled;

  /// Lobby code
  final String lobby;

  /// Device type ("bike" or "scooter")
  final String type;

  /// Order in rack
  final String rackOrder;

  const ThingAttributes({
    this.enabled = '1',
    this.lobby = '',
    this.type = 'bike',
    this.rackOrder = '0',
  });

  factory ThingAttributes.fromMap(Map<String, String>? map) {
    if (map == null) return const ThingAttributes();

    return ThingAttributes(
      enabled: map['enabled'] ?? '1',
      lobby: map['lobby'] ?? '',
      type: map['type'] ?? 'bike',
      rackOrder: map['rackOrder'] ?? '0',
    );
  }

  Map<String, String> toMap() {
    return {
      'enabled': enabled,
      'lobby': lobby,
      'type': type,
      'rackOrder': rackOrder,
    };
  }

  ThingAttributes copyWith({
    String? enabled,
    String? lobby,
    String? type,
    String? rackOrder,
  }) {
    return ThingAttributes(
      enabled: enabled ?? this.enabled,
      lobby: lobby ?? this.lobby,
      type: type ?? this.type,
      rackOrder: rackOrder ?? this.rackOrder,
    );
  }

  @override
  List<Object?> get props => [enabled, lobby, type, rackOrder];
}

/// Represents a rack (collection of locks sharing a certificate)
class Rack extends Equatable {
  /// Environment (dev, test, prod)
  final String environment;

  /// Rack name (e.g., RACK01)
  final String rackName;

  /// Lobby code
  final String lobby;

  /// Certificate ARN
  final String? certificateArn;

  /// Master thing
  final Thing? master;

  /// Lock things in this rack
  final List<Thing> locks;

  const Rack({
    required this.environment,
    required this.rackName,
    required this.lobby,
    this.certificateArn,
    this.master,
    this.locks = const [],
  });

  /// Full rack identifier (e.g., dev-RACK01)
  String get fullName => '$environment-$rackName';

  /// Number of bike locks
  int get bikeCount => locks.where((l) => l.attributes.type == 'bike').length;

  /// Number of scooter locks
  int get scooterCount =>
      locks.where((l) => l.attributes.type == 'scooter').length;

  @override
  List<Object?> get props => [
        environment,
        rackName,
        lobby,
        certificateArn,
        master,
        locks,
      ];
}
