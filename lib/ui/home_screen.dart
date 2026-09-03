import 'package:flutter/material.dart';

import '../services/contact_service.dart';
import '../services/geo_service.dart';
import '../services/identity_service.dart';
import '../services/message_store.dart';
import '../services/permission_service.dart';
import '../services/room_service.dart';
import '../services/routing_service.dart';
import '../services/transport_bluetooth.dart';
import '../services/transport_wifi_direct.dart';
import '../services/backup_service.dart';
import '../services/power_mode.dart';
import '../theme/mesh_theme.dart';
import 'widgets/permission_gate.dart';
import 'widgets/chat_panel.dart';
import 'widgets/contacts_panel.dart';
import 'widgets/animated_card.dart';
import 'widgets/rooms_panel.dart';
import 'widgets/nearby_panel.dart';
import 'widgets/control_panel.dart';
import 'widgets/about_screen.dart';
import 'widgets/restore_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.identity,
    required this.permissions,
    required this.routing,
    required this.bluetooth,
    required this.wifi,
    required this.contacts,
    required this.rooms,
    required this.geo,
    required this.store,
    required this.backup,
    required this.power,
  });

  final IdentityService identity;
  final PermissionService permissions;
  final RoutingService routing;
  final BluetoothTransport bluetooth;
  final WifiDirectTransport wifi;
  final ContactService contacts;
  final RoomService rooms;
  final GeoService geo;
  final MessageStore store;
  final BackupService backup;
  final PowerModeService power;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  bool _restored = false;
  String _restoredOrigin = '';

  @override
  void initState() {
    super.initState();
    widget.routing.addListener(_onChange);
    widget.contacts.addListener(_onChange);
    widget.rooms.addListener(_onChange);
    widget.backup.addListener(_onChange);
    _refreshRestoreFlag();
  }

  Future<void> _refreshRestoreFlag() async {
    final r = await widget.backup.isRestored();
    final origin = await widget.backup.restoredOrigin() ?? '';
    if (mounted) {
      setState(() {
        _restored = r;
        _restoredOrigin = origin;
      });
    }
  }

  @override
  void dispose() {
    widget.routing.removeListener(_onChange);
    widget.contacts.removeListener(_onChange);
    widget.rooms.removeListener(_onChange);
    widget.backup.removeListener(_onChange);
    _tabs.dispose();
    super.dispose();
  }

  void _onChange() => setState(() {});

  Future<void> _ensurePermissions() async {
    final report = await widget.permissions.requestAll();
    if (!mounted) return;
    if (!widget.permissions.canMesh(report)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Нужны разрешения: BT, локация, уведомления.\n${report.describe()}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      identity: widget.identity,
      onGranted: () async {
        await _ensurePermissions();
        if (!widget.routing.isRunning) widget.routing.start();
      },
      builder: (ctx) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: MeshTheme.bgGradient),
          child: SafeArea(
            child: Column(
              children: [
                if (_restored)
                  RestoredBanner(
                    originAlias: widget.identity.alias,
                    originNodeId: _restoredOrigin,
                    onDismiss: () async {
                      await widget.backup.clearRestoreFlag();
                      if (mounted) {
                        setState(() {
                          _restored = false;
                        });
                      }
                    },
                  ),
                _Header(identity: widget.identity, routing: widget.routing),
                _StatusBar(
                  routing: widget.routing,
                  contacts: widget.contacts,
                  rooms: widget.rooms,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: TabBarView(
                      key: ValueKey(_tabs.index),
                      controller: _tabs,
                      children: [
                      ChatPanel(
                        identity: widget.identity,
                        routing: widget.routing,
                        contacts: widget.contacts,
                      ),
                      RoomsPanel(
                        identity: widget.identity,
                        rooms: widget.rooms,
                        routing: widget.routing,
                        contacts: widget.contacts,
                        geo: widget.geo,
                      ),
                      ContactsPanel(
                        identity: widget.identity,
                        contacts: widget.contacts,
                        routing: widget.routing,
                      ),
                      NearbyPanel(
                        routing: widget.routing,
                        contacts: widget.contacts,
                      ),
                      ControlPanel(
                        identity: widget.identity,
                        routing: widget.routing,
                        bluetooth: widget.bluetooth,
                        wifi: widget.wifi,
                        geo: widget.geo,
                        contacts: widget.contacts,
                        store: widget.store,
                        backup: widget.backup,
                        power: widget.power,
                      ),
                    ],
                    ),
                  ),
                ),
                _BottomBar(controller: _tabs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.identity, required this.routing});
  final IdentityService identity;
  final RoutingService routing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: MeshTheme.headerGradient,
                boxShadow: [
                  BoxShadow(
                    color: MeshTheme.primary.withValues(alpha: 0.5),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(Icons.hub_rounded, color: Colors.black),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BridgeMesh',
                  style: TextStyle(
                    color: MeshTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  '${identity.alias} • ${identity.shortNodeId}',
                  style: const TextStyle(
                    color: MeshTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _NetworkIndicator(
            alive: routing.neighbors.isNotEmpty,
            count: routing.neighbors.length,
          ),
        ],
      ),
    );
  }
}

class _NetworkIndicator extends StatelessWidget {
  const _NetworkIndicator({required this.alive, required this.count});
  final bool alive;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = alive ? MeshTheme.success : MeshTheme.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alive) PulsingDot(color: color, size: 8)
          else Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            alive ? '$count узлов' : 'поиск...',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.routing,
    required this.contacts,
    required this.rooms,
  });
  final RoutingService routing;
  final ContactService contacts;
  final RoomService rooms;

  @override
  Widget build(BuildContext context) {
    final n = routing.neighbors.length;
    final c = contacts.contacts.length;
    final r = rooms.currentRoom;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _stat('Соседей', n.toString(), Icons.podcasts),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: _stat('Контактов', c.toString(), Icons.people_outline),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 5,
            child: _stat(
              'Город',
              r.isEmpty ? '...' : r,
              Icons.location_city_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData ic) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(ic, color: MeshTheme.primary, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: MeshTheme.textSecondary,
                    fontSize: 9,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: MeshTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: TabBar(
          controller: controller,
          // Равномерное распределение по ширине, центрирование.
          isScrollable: false,
          tabAlignment: TabAlignment.center,
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: MeshTheme.primary, width: 2),
            insets: EdgeInsets.symmetric(horizontal: 16),
          ),
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: MeshTheme.primary,
          unselectedLabelColor: MeshTheme.textSecondary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          tabs: const [
            Tab(
              icon: Icon(Icons.chat_bubble_outline, size: 22),
              text: 'Чат',
              height: 56,
            ),
            Tab(
              icon: Icon(Icons.location_city_outlined, size: 22),
              text: 'Город',
              height: 56,
            ),
            Tab(
              icon: Icon(Icons.contacts_outlined, size: 22),
              text: 'Люди',
              height: 56,
            ),
            Tab(
              icon: Icon(Icons.podcasts, size: 22),
              text: 'Рядом',
              height: 56,
            ),
            Tab(
              icon: Icon(Icons.tune, size: 22),
              text: 'Ещё',
              height: 56,
            ),
          ],
        ),
      ),
    );
  }
}
