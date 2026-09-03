import 'package:flutter/material.dart';

import '../../models/contact.dart';
import '../../services/contact_service.dart';
import '../../services/routing_service.dart';
import '../../theme/mesh_theme.dart';

class NearbyPanel extends StatefulWidget {
  const NearbyPanel({
    super.key,
    required this.routing,
    required this.contacts,
  });

  final RoutingService routing;
  final ContactService contacts;

  @override
  State<NearbyPanel> createState() => _NearbyPanelState();
}

class _NearbyPanelState extends State<NearbyPanel> {
  @override
  void initState() {
    super.initState();
    widget.routing.addListener(_onChange);
    widget.contacts.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.routing.removeListener(_onChange);
    widget.contacts.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final neighbors = widget.routing.neighbors;
    final learned = widget.contacts.learned.toList();
    // Объединяем физических соседей и тех, кого видели в mesh.
    final all = <_NearbyEntry>[];
    for (final n in neighbors) {
      all.add(_NearbyEntry(
        name: n.name,
        shortId: _extractId(n.name, n.id),
        rssi: n.rssi,
        transport: n.transport,
        contact: widget.contacts.byId(_extractId(n.name, n.id)),
        online: true,
      ));
    }
    // Добавим тех, кого не видели в эфире прямо сейчас, но помним.
    for (final c in learned) {
      if (all.any((e) => e.shortId == c.shortId)) continue;
      all.add(_NearbyEntry(
        name: c.alias,
        shortId: c.shortId,
        rssi: -100,
        transport: 'mesh',
        contact: c,
        online: false,
      ));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MeshTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: MeshTheme.headerGradient,
                  boxShadow: [
                    BoxShadow(
                      color: MeshTheme.primary.withValues(alpha: 0.5),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Icon(Icons.podcasts,
                    color: Colors.black, size: 32),
              ),
              const SizedBox(height: 12),
              Text(
                'Рядом: ${neighbors.length}',
                style: const TextStyle(
                  color: MeshTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'BridgeMesh ищет соседей по Bluetooth и Wi-Fi.\n'
                'Любой, кто откроет приложение рядом, появится здесь.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (all.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'Пока никого рядом. Подождите — сеть растёт\n'
              'по мере того, как люди включают приложение.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MeshTheme.textSecondary),
            ),
          )
        else
          ...all.map((e) => _NearbyTile(
                entry: e,
                onAdd: () {
                  final id = e.contact?.nodeId ?? _extractId(e.name, e.shortId);
                  if (id.isEmpty) return;
                  widget.contacts.addContact(id, note: 'Добавлен из «Кто рядом»');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${e.name} добавлен в контакты'),
                    ),
                  );
                },
              )),
      ],
    );
  }

  String _extractId(String name, String fallback) {
    // Попытка вытащить «настоящий» nodeId из neighbor: обычно он в id.
    if (fallback.isEmpty) return '';
    return fallback;
  }
}

class _NearbyEntry {
  final String name;
  final String shortId;
  final int rssi;
  final String transport;
  final Contact? contact;
  final bool online;
  _NearbyEntry({
    required this.name,
    required this.shortId,
    required this.rssi,
    required this.transport,
    required this.contact,
    required this.online,
  });
}

class _NearbyTile extends StatelessWidget {
  const _NearbyTile({required this.entry, required this.onAdd});
  final _NearbyEntry entry;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final rssiBars = entry.rssi >= -60
        ? 4
        : entry.rssi >= -70
            ? 3
            : entry.rssi >= -80
                ? 2
                : 1;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MeshTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: entry.online
                    ? MeshTheme.primary.withValues(alpha: 0.15)
                    : MeshTheme.textSecondary.withValues(alpha: 0.15),
                child: Text(
                  entry.name.isNotEmpty
                      ? entry.name.substring(0, 1).toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: entry.online
                        ? MeshTheme.primary
                        : MeshTheme.textSecondary,
                  ),
                ),
              ),
              if (entry.online)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: MeshTheme.success,
                      border: Border.all(color: MeshTheme.surface, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: TextStyle(
                    color: entry.online
                        ? MeshTheme.textPrimary
                        : MeshTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      entry.shortId,
                      style: const TextStyle(
                        color: MeshTheme.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${entry.transport} • ${entry.rssi} dBm',
                      style: const TextStyle(
                        color: MeshTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: List.generate(4, (i) {
              final filled = i < rssiBars;
              return Container(
                width: 3,
                height: 4 + i * 3.0,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: filled
                      ? MeshTheme.primary
                      : MeshTheme.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              entry.contact != null ? Icons.check_circle : Icons.person_add_alt_1,
              color: entry.contact != null
                  ? MeshTheme.success
                  : MeshTheme.primary,
            ),
            tooltip: entry.contact != null ? 'В контактах' : 'Добавить',
            onPressed: entry.contact != null ? null : onAdd,
          ),
        ],
      ),
    );
  }
}
