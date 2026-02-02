import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

import 'features/locks/presentation/screens/locks_screen.dart';
import 'features/things/presentation/screens/things_screen.dart';
import 'features/certificates/presentation/screens/certificates_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/aws_config/presentation/screens/aws_config_screen.dart';

// Intents for keyboard shortcuts
class NavigateToTabIntent extends Intent {
  final int tabIndex;
  const NavigateToTabIntent(this.tabIndex);
}

/// Main application widget with platform-specific theming
class IotBikesApp extends ConsumerStatefulWidget {
  const IotBikesApp({super.key});

  @override
  ConsumerState<IotBikesApp> createState() => _IotBikesAppState();
}

class _IotBikesAppState extends ConsumerState<IotBikesApp> {
  int _selectedIndex = 0;

  void _navigateToTab(int index) {
    if (index >= 0 && index <= 4) {
      setState(() => _selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wrap with shortcuts for keyboard navigation
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Cmd/Ctrl + 1-5 for tab navigation
        LogicalKeySet(
          Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control,
          LogicalKeyboardKey.digit1,
        ): const NavigateToTabIntent(0),
        LogicalKeySet(
          Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control,
          LogicalKeyboardKey.digit2,
        ): const NavigateToTabIntent(1),
        LogicalKeySet(
          Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control,
          LogicalKeyboardKey.digit3,
        ): const NavigateToTabIntent(2),
        LogicalKeySet(
          Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control,
          LogicalKeyboardKey.digit4,
        ): const NavigateToTabIntent(3),
        LogicalKeySet(
          Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control,
          LogicalKeyboardKey.digit5,
        ): const NavigateToTabIntent(4),
        // Cmd/Ctrl + , for settings
        LogicalKeySet(
          Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control,
          LogicalKeyboardKey.comma,
        ): const NavigateToTabIntent(4),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          NavigateToTabIntent: CallbackAction<NavigateToTabIntent>(
            onInvoke: (intent) => _navigateToTab(intent.tabIndex),
          ),
        },
        child: Focus(
          autofocus: true,
          child: _buildPlatformApp(),
        ),
      ),
    );
  }

  Widget _buildPlatformApp() {
    if (Platform.isMacOS) {
      return _buildMacOSApp();
    } else if (Platform.isWindows) {
      return _buildWindowsApp();
    }
    return _buildMaterialApp();
  }

  Widget _buildMacOSApp() {
    return MacosApp(
      title: 'IoT Bikes Virtual Locks',
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      themeMode: ThemeMode.system,
      home: MacosWindow(
        sidebar: Sidebar(
          minWidth: 220,
          maxWidth: 300,
          startWidth: 220,
          isResizable: false,
          builder: (context, scrollController) {
            // Use explicit light colors for dark sidebar background
            const unselectedColor = Color(0xFFE0E0E0);
            return SidebarItems(
              currentIndex: _selectedIndex,
              onChanged: (index) => setState(() => _selectedIndex = index),
              scrollController: scrollController,
              itemSize: SidebarItemSize.large,
              items: [
                SidebarItem(
                  leading: const MacosIcon(Icons.lock_outlined, color: unselectedColor),
                  label: const Text('Virtual Locks', style: TextStyle(color: unselectedColor)),
                ),
                SidebarItem(
                  leading: const MacosIcon(Icons.devices_outlined, color: unselectedColor),
                  label: const Text('Things', style: TextStyle(color: unselectedColor)),
                ),
                SidebarItem(
                  leading: const MacosIcon(Icons.verified_user_outlined, color: unselectedColor),
                  label: const Text('Certificates', style: TextStyle(color: unselectedColor)),
                ),
                SidebarItem(
                  leading: const MacosIcon(Icons.cloud_outlined, color: unselectedColor),
                  label: const Text('AWS Config', style: TextStyle(color: unselectedColor)),
                ),
                SidebarItem(
                  leading: const MacosIcon(Icons.settings_outlined, color: unselectedColor),
                  label: const Text('Settings', style: TextStyle(color: unselectedColor)),
                ),
              ],
            );
          },
        ),
        // Wrap child with MaterialApp for Scaffold/SnackBar support
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          home: _getSelectedScreen(),
        ),
      ),
    );
  }

  Widget _buildWindowsApp() {
    return fluent.FluentApp(
      title: 'IoT Bikes Virtual Locks',
      theme: fluent.FluentThemeData.light(),
      darkTheme: fluent.FluentThemeData.dark(),
      themeMode: ThemeMode.system,
      home: fluent.NavigationView(
        pane: fluent.NavigationPane(
          selected: _selectedIndex,
          onChanged: (index) => setState(() => _selectedIndex = index),
          displayMode: fluent.PaneDisplayMode.compact,
          items: [
            fluent.PaneItem(
              icon: const Icon(fluent.FluentIcons.lock),
              title: const Text('Virtual Locks'),
              body: const LocksScreen(),
            ),
            fluent.PaneItem(
              icon: const Icon(fluent.FluentIcons.devices3),
              title: const Text('Things'),
              body: const ThingsScreen(),
            ),
            fluent.PaneItem(
              icon: const Icon(fluent.FluentIcons.certificate),
              title: const Text('Certificates'),
              body: const CertificatesScreen(),
            ),
            fluent.PaneItem(
              icon: const Icon(fluent.FluentIcons.cloud),
              title: const Text('AWS Config'),
              body: const AwsConfigScreen(),
            ),
          ],
          footerItems: [
            fluent.PaneItem(
              icon: const Icon(fluent.FluentIcons.settings),
              title: const Text('Settings'),
              body: const SettingsScreen(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialApp() {
    return MaterialApp(
      title: 'IoT Bikes Virtual Locks',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.lock_outlined),
                  selectedIcon: Icon(Icons.lock),
                  label: Text('Locks'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.devices_outlined),
                  selectedIcon: Icon(Icons.devices),
                  label: Text('Things'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.verified_user_outlined),
                  selectedIcon: Icon(Icons.verified_user),
                  label: Text('Certs'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.cloud_outlined),
                  selectedIcon: Icon(Icons.cloud),
                  label: Text('AWS'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: _getSelectedScreen()),
          ],
        ),
      ),
    );
  }

  Widget _getSelectedScreen() {
    switch (_selectedIndex) {
      case 0:
        return const LocksScreen();
      case 1:
        return const ThingsScreen();
      case 2:
        return const CertificatesScreen();
      case 3:
        return const AwsConfigScreen();
      case 4:
        return const SettingsScreen();
      default:
        return const LocksScreen();
    }
  }
}
