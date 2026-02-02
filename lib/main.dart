import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/utils/logger.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging
  AppLogger.init();
  AppLogger.info('Starting IoT Bikes Virtual Locks Manager');

  // Initialize Hive for local storage
  final appDir = await getApplicationSupportDirectory();
  await Hive.initFlutter(appDir.path);

  // Initialize storage service
  await StorageService.instance.initialize();

  AppLogger.info('Running on platform: ${Platform.operatingSystem}');

  runApp(
    const ProviderScope(
      child: IotBikesApp(),
    ),
  );
}
