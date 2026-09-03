import 'package:flutter/material.dart';

import '../../models/contact.dart';
import '../../models/neighbor.dart';
import '../../services/contact_service.dart';
import '../../services/dialogs_service.dart';
import '../../services/identity_service.dart';
import '../../services/routing_service.dart';
import '../../theme/mesh_theme.dart';
import 'chat_panel.dart';

/// Вкладка «Рядом»: кто виден прямо сейчас по BLE / Wi-Fi Direct.
///
/// Можно быстро добавить в контакты или сразу написать личное
/// сообщение — не надо сканировать QR.
class NearbyPanel extends StatefulWidget {
  const NearbyPanel({
    super.key,
    required this.routing,
    required this.contacts,
    required this.identity,
    required this.dialogs,
  });

  final RoutingService routing;
  final ContactService contacts;
  final IdentityService identity;
  final DialogsService dialogs;

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
    // myNodeId (не используется)
    // Соединяем соседей с контактами по их nodeId.
    final byNodeId = <String, Contact>{};
    for (final n in neighbors) {
      final c = widget.contacts.byId(n.id);
      if (c != null) byNodeId[n.id] = c;
    }
    return Container(
      decoration: const BoxDecoration(gradient: MeshTheme.bgGradient),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(visible: neighbors.length),
            Expanded(
              child: neighbors.isEmpty
                  ? const _Empty()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: neighbors.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 4),
                      itemBuilder: (ctx, i) {
                        final n = neighbors[i];
                        final contact = byNodeId[n.id];
                        return _Tile(
                          name: contact?.displayName ?? n.name,
                          nodeId: n.id,
                          addr: n.addr ?? '',
                          transport: n.transport,
                          rssi: n.rssi,
                          added: contact != null,
                          onAdd: () => _addToContacts(n, contact),
                          onMessage: () => _messagePeer(n, contact),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MeshTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.share_outlined,
                        size: 18, color: MeshTheme.primary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Поделитесь своим кодом — нажмите «QR» внизу.',
                        style: TextStyle(
                          color: MeshTheme.textPrimary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToContacts(Neighbor n, Contact? existing) async {
    if (existing != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${existing.displayName} уже в контактах')),
      );
      return;
    }
    if (n.id == widget.identity.nodeId) return; // нельзя добавить самого себя
    final ctrl = TextEditingController(text: n.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MeshTheme.surface,
        title: const Text(
          'Добавить в контакты',
          style: TextStyle(color: MeshTheme.textPrimary),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: MeshTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Имя',
            labelStyle: TextStyle(color: MeshTheme.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await widget.contacts.addContact(
      n.id,
      note: 'Добавлен из «Рядом»',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name добавлен в контакты')),
    );
  }

  Future<void> _messagePeer(Neighbor n, Contact? existing) async {
    final peerName = existing?.displayName ?? n.name;
    final peerId = existing?.alias ?? n.id;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPanel(
          identity: widget.identity,
          routing: widget.routing,
          contacts: widget.contacts,
          dialogs: widget.dialogs,
          peerId: peerId,
          peerName: peerName,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.visible});
  final int visible;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          const Icon(Icons.podcasts,
              color: MeshTheme.primary, size: 26),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Рядом',
              style: TextStyle(
                color: MeshTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: MeshTheme.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$visible человек',
              style: const TextStyle(
                color: MeshTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MeshTheme.primary.withValues(alpha: 0.08),
                border: Border.all(
                  color: MeshTheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(Icons.podcasts,
                  size: 44, color: MeshTheme.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'Пока никого рядом',
              style: TextStyle(
                color: MeshTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Включите Bluetooth и геолокацию. BridgeMesh ищет '
              'соседей в радиусе ~30–100 м по Bluetooth и '
              'до 200 м по Wi-Fi Direct.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MeshTheme.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.name,
    required this.nodeId,
    required this.addr,
    required this.transport,
    required this.rssi,
    required this.added,
    required this.onAdd,
    required this.onMessage,
  });
  final String name;
  final String nodeId;
  final String addr;
  final String transport;
  final int rssi;
  final bool added;
  final VoidCallback onAdd;
  final VoidCallback onMessage;

  String get _signal {
    if (rssi >= -60) return 'Отлично';
    if (rssi >= -75) return 'Хорошо';
    if (rssi >= -85) return 'Слабо';
    return 'Далеко';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MeshTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: added
              ? MeshTheme.primary.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.04),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor:
                MeshTheme.primary.withValues(alpha: 0.16),
            child: Text(
              name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
              style: const TextStyle(color: MeshTheme.primary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                          color: MeshTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (added) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: MeshTheme.primary
                              .withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'контакт',
                          style: TextStyle(
                            color: MeshTheme.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${_iconFor(transport)} $transport • $_signal',
                  style: const TextStyle(
                    color: MeshTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              added ? Icons.check_circle : Icons.person_add_alt_1,
              color: added ? MeshTheme.primary : MeshTheme.textPrimary,
            ),
            tooltip: added ? 'В контактах' : 'Добавить в контакты',
            onPressed: added ? null : onAdd,
          ),
          IconButton(
            icon: const Icon(Icons.send, color: MeshTheme.primary),
            tooltip: 'Написать',
            onPressed: onMessage,
          ),
        ],
      ),
    );
  }

  String _iconFor(String t) {
    if (t.toLowerCase().contains('bluetooth')) return '📡';
    if (t.toLowerCase().contains('wifi')) return '📶';
    return '🔗';
  }
}
