import 'package:flutter/material.dart';
import 'services/paths.dart';
import 'services/server_manager.dart';
import 'pages/dashboard_page.dart';
import 'pages/config_page.dart';
import 'pages/patch_page.dart';
import 'pages/panel_page.dart';
import 'pages/save_tools_page.dart';

void main() {
  Paths.init();
  runApp(const StarpointLauncherApp());
}

class StarpointLauncherApp extends StatelessWidget {
  const StarpointLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StarPoint CN 启动器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        useMaterial3: true,
      ),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

enum NavItem { dashboard, config, patch, panel, saveTools }

class _ShellState extends State<Shell> {
  NavItem _selected = NavItem.dashboard;
  final _server = ServerManager();

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navItems = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('总览'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('配置'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.build_outlined),
        selectedIcon: Icon(Icons.build),
        label: Text('补丁'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.web_outlined),
        selectedIcon: Icon(Icons.web),
        label: Text('面板'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.inventory_2_outlined),
        selectedIcon: Icon(Icons.inventory_2),
        label: Text('存档'),
      ),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selected.index,
            onDestinationSelected: (i) => setState(() => _selected = NavItem.values[i]),
            extended: MediaQuery.of(context).size.width > 1100,
            destinations: navItems,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(Icons.gamepad, size: 36, color: Color(0xFF6750A4)),
                  SizedBox(height: 4),
                  Text('StarPoint', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildPage()),
        ],
      ),
    );
  }

  Widget _buildPage() {
    switch (_selected) {
      case NavItem.dashboard:
        return DashboardPage(server: _server);
      case NavItem.config:
        return const ConfigPage();
      case NavItem.patch:
        return const PatchPage();
      case NavItem.panel:
        return PanelPage(server: _server);
      case NavItem.saveTools:
        return SaveToolsPage(server: _server);
    }
  }
}
