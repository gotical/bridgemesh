import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/room.dart';
import '../../services/contact_service.dart';
import '../../services/geo_service.dart';
import '../../services/identity_service.dart';
import '../../services/room_service.dart';
import '../../services/routing_service.dart';
import '../../theme/mesh_theme.dart';

class RoomsPanel extends StatefulWidget {
  const RoomsPanel({
    super.key,
    required this.identity,
    required this.rooms,
    required this.routing,
    required this.contacts,
    required this.geo,
  });

  final IdentityService identity;
  final RoomService rooms;
  final RoutingService routing;
  final ContactService contacts;
  final GeoService geo;

  @override
  State<RoomsPanel> createState() => _RoomsPanelState();
}

class _RoomsPanelState extends State<RoomsPanel> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.rooms.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.rooms.removeListener(_onChange);
    _ctrl.dispose();
    super.dispose();
  }

  void _onChange() => setState(() {});

  Future<void> _send() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty) return;
    _ctrl.clear();
    await widget.routing.sendRoomMessage(txt);
  }

  @override
  Widget build(BuildContext context) {
    final city = widget.rooms.currentRoom.isEmpty
        ? 'Не определён'
        : widget.rooms.currentRoom;
    final msgs = widget.rooms.messagesOf(city);

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MeshTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_city, color: MeshTheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      city,
                      style: const TextStyle(
                        color: MeshTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.rooms.currentRoomSlug,
                      style: const TextStyle(
                        color: MeshTheme.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.geo.position != null)
                Text(
                  '${widget.geo.position!.latitude.toStringAsFixed(2)}, '
                  '${widget.geo.position!.longitude.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: MeshTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: msgs.isEmpty
              ? _EmptyRoom(city: city)
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) => _MessageBubble(
                    msg: msgs[i],
                    isMine: msgs[i].fromId == widget.identity.nodeId,
                    onAdd: msgs[i].fromId == widget.identity.nodeId
                        ? null
                        : () => _addAuthorToContacts(msgs[i]),
                  ),
                ),
        ),
        _Composer(controller: _ctrl, onSend: _send),
      ],
    );
  }

  Future<void> _addAuthorToContacts(RoomMessage m) async {
    await widget.contacts.addContact(m.fromId, note: 'Из чата ${widget.rooms.currentRoom}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${m.fromAlias} добавлен в контакты',
        ),
      ),
    );
  }
}

class _EmptyRoom extends StatelessWidget {
  const _EmptyRoom({required this.city});
  final String city;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 56,
              color: MeshTheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'Чат города $city',
              style: const TextStyle(
                color: MeshTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Сообщения хранятся у каждого узла. Когда участники '
              'встречаются, они дополняют друг друга новыми постами.\n'
              'GPS создаёт комнату автоматически.',
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.msg,
    required this.isMine,
    this.onAdd,
  });
  final RoomMessage msg;
  final bool isMine;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
    );
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isMine ? MeshTheme.headerGradient : null,
          color: isMine ? null : MeshTheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          border: isMine
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Row(
                children: [
                  Flexible(
                    child: Text(
                      msg.fromAlias,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MeshTheme.secondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onAdd != null) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Добавить в контакты',
                      child: InkWell(
                        onTap: onAdd,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: MeshTheme.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_add_alt_1,
                                size: 12,
                                color: MeshTheme.primary,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'в контакты',
                                style: TextStyle(
                                  color: MeshTheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            if (!isMine) const SizedBox(height: 2),
            Text(
              msg.text,
              style: TextStyle(
                color: isMine ? Colors.black : MeshTheme.textPrimary,
                fontSize: 15,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    color: isMine ? Colors.black54 : MeshTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                if (msg.hops > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${msg.hops} hop',
                    style: TextStyle(
                      color: isMine ? Colors.black54 : MeshTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: MeshTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: TextField(
                controller: controller,
                style: const TextStyle(color: MeshTheme.textPrimary),
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Написать в город...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: onSend,
            style: IconButton.styleFrom(
              backgroundColor: MeshTheme.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.all(14),
            ),
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}
