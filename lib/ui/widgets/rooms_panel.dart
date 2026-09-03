import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/room.dart';
import '../../services/contact_service.dart';
import '../../services/dialogs_service.dart';
import '../../services/geo_service.dart';
import '../../services/identity_service.dart';
import '../../services/room_service.dart';
import '../../services/routing_service.dart';
import '../../theme/mesh_theme.dart';
import 'chat_panel.dart';

/// Вкладка «Город»: городской чат и общий чат.
///
/// Город определяется по GPS (или вручную). Переехали из
/// Рыбинска в Ярославль — попали в чат Ярославля. История
/// всех городов остаётся локально.
///
/// Общий чат — отдельная комната, доступна всегда. История
/// переезжает с телефоном.
class RoomsPanel extends StatefulWidget {
  const RoomsPanel({
    super.key,
    required this.identity,
    required this.rooms,
    required this.routing,
    required this.contacts,
    required this.geo,
    required this.dialogs,
  });

  final IdentityService identity;
  final RoomService rooms;
  final RoutingService routing;
  final ContactService contacts;
  final GeoService geo;
  final DialogsService dialogs;

  @override
  State<RoomsPanel> createState() => _RoomsPanelState();
}

class _RoomsPanelState extends State<RoomsPanel>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  late final TabController _tabs =
      TabController(length: 2, vsync: this);

  String _citySlug() => widget.rooms.currentRoomSlug;

  @override
  void initState() {
    super.initState();
    widget.rooms.addListener(_onChange);
    widget.geo.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.rooms.removeListener(_onChange);
    widget.geo.removeListener(_onChange);
    _tabs.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChange() => setState(() {});

  Future<void> _send() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty) return;
    _ctrl.clear();
    final isGlobal = _tabs.index == 1;
    final slug = isGlobal ? RoomService.globalSlug : _citySlug();
    await widget.routing.sendRoomMessage(txt, slug: slug);
  }

  @override
  Widget build(BuildContext context) {
    final citySlug = _citySlug();
    final cityName = widget.rooms.nameOf(citySlug);
    return Container(
      decoration: const BoxDecoration(gradient: MeshTheme.bgGradient),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              cityName: cityName,
              citySlug: citySlug,
              hasGps: widget.geo.hasGpsFix,
              onDetect: () => _detectCity(),
            ),
            _SubTabs(controller: _tabs),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: TabBarView(
                  key: ValueKey(_tabs.index),
                  controller: _tabs,
                  children: [
                    _RoomView(
                      key: const ValueKey('city'),
                      identity: widget.identity,
                      rooms: widget.rooms,
                      contacts: widget.contacts,
                      routing: widget.routing,
                      dialogs: widget.dialogs,
                      geo: widget.geo,
                      slug: citySlug,
                      title: cityName,
                      subtitle: 'Общий чат жителей города',
                      icon: Icons.location_city_outlined,
                    ),
                    _RoomView(
                      key: const ValueKey('global'),
                      identity: widget.identity,
                      rooms: widget.rooms,
                      contacts: widget.contacts,
                      routing: widget.routing,
                      dialogs: widget.dialogs,
                      geo: widget.geo,
                      slug: RoomService.globalSlug,
                      title: 'Общий чат',
                      subtitle: 'Видят все в mesh, история с вами',
                      icon: Icons.public,
                    ),
                  ],
                ),
              ),
            ),
            _Composer(controller: _ctrl, onSend: _send),
          ],
        ),
      ),
    );
  }

  Future<void> _detectCity() async {
    final ok = await widget.geo.tryDetectNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Город обновлён: ${widget.rooms.currentRoom}'
              : 'Не удалось определить. Разрешите геолокацию.',
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.cityName,
    required this.citySlug,
    required this.hasGps,
    required this.onDetect,
  });
  final String cityName;
  final String citySlug;
  final bool hasGps;
  final VoidCallback onDetect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
      child: Row(
        children: [
          const Icon(Icons.location_city_outlined,
              color: MeshTheme.primary, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cityName,
                  style: const TextStyle(
                    color: MeshTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  hasGps ? 'GPS активен' : 'GPS не активен',
                  style: const TextStyle(
                    color: MeshTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.gps_fixed, color: MeshTheme.primary),
            tooltip: 'Уточнить город',
            onPressed: onDetect,
          ),
        ],
      ),
    );
  }
}

class _SubTabs extends StatelessWidget {
  const _SubTabs({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      decoration: BoxDecoration(
        color: MeshTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: TabBar(
        controller: controller,
        onTap: (_) => (context as Element).markNeedsBuild(),
        indicator: BoxDecoration(
          color: MeshTheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.black,
        unselectedLabelColor: MeshTheme.textPrimary,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(
            height: 36,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_city, size: 16),
                SizedBox(width: 6),
                Text('Город'),
              ],
            ),
          ),
          Tab(
            height: 36,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.public, size: 16),
                SizedBox(width: 6),
                Text('Общий'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomView extends StatefulWidget {
  const _RoomView({
    super.key,
    required this.identity,
    required this.rooms,
    required this.contacts,
    required this.routing,
    required this.dialogs,
    required this.geo,
    required this.slug,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final IdentityService identity;
  final RoomService rooms;
  final ContactService contacts;
  final RoutingService routing;
  final DialogsService dialogs;
  final GeoService geo;
  final String slug;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  State<_RoomView> createState() => _RoomViewState();
}

class _RoomViewState extends State<_RoomView> {
  @override
  void initState() {
    super.initState();
    widget.rooms.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.rooms.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final msgs = widget.rooms.messagesOf(widget.slug);
    final hasCity = widget.slug != RoomService.globalSlug &&
        widget.slug == widget.rooms.currentRoomSlug &&
        widget.geo.hasGpsFix;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MeshTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: MeshTheme.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: MeshTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        color: MeshTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: msgs.isEmpty
              ? _EmptyRoom(
                  title: widget.title,
                  icon: widget.icon,
                  hint: hasCity
                      ? 'Пока никто не написал. Напишите первым!'
                      : 'Город не определён. Нажмите «GPS» сверху, '
                          'чтобы попасть в чат своего города.',
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) => _MessageBubble(
                    msg: msgs[i],
                    isMine: msgs[i].fromId == widget.identity.nodeId,
                    onTap: msgs[i].fromId == widget.identity.nodeId
                        ? null
                        : () => _onMessageTap(msgs[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _onMessageTap(RoomMessage m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MeshTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MeshTheme.textSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1,
                  color: MeshTheme.primary),
              title: const Text(
                'Добавить в контакты',
                style: TextStyle(color: MeshTheme.textPrimary),
              ),
              subtitle: Text(
                m.fromAlias,
                style: const TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'add'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.send, color: MeshTheme.primary),
              title: const Text(
                'Написать личное',
                style: TextStyle(color: MeshTheme.textPrimary),
              ),
              subtitle: Text(
                'Диалог с ${m.fromAlias}',
                style: const TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'msg'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == 'add') {
      await widget.contacts.addContact(
        m.fromId,
        note: 'Добавлен из чата',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${m.fromAlias} добавлен в контакты'),
        ),
      );
    } else if (action == 'msg') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPanel(
            identity: widget.identity,
            routing: widget.routing,
            contacts: widget.contacts,
            dialogs: widget.dialogs,
            peerId: m.fromAlias,
            peerName: m.fromAlias,
          ),
        ),
      );
    }
  }
}

class _EmptyRoom extends StatelessWidget {
  const _EmptyRoom({required this.title, required this.icon, required this.hint});
  final String title;
  final IconData icon;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MeshTheme.primary.withValues(alpha: 0.08),
                border: Border.all(
                  color: MeshTheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Icon(icon, size: 40, color: MeshTheme.primary),
            ),
            const SizedBox(height: 14),
            Text(
              'Тут пока тихо',
              style: const TextStyle(
                color: MeshTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MeshTheme.textSecondary,
                fontSize: 12,
                height: 1.4,
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
    required this.onTap,
  });
  final RoomMessage msg;
  final bool isMine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
    );
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: isMine ? MeshTheme.primary : MeshTheme.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isMine ? 14 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 14),
            ),
            border: isMine
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMine)
                Text(
                  msg.fromAlias,
                  style: const TextStyle(
                    color: MeshTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (!isMine) const SizedBox(height: 2),
              Text(
                msg.text,
                style: TextStyle(
                  color: isMine ? Colors.black : MeshTheme.textPrimary,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 3),
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
                  if (!isMine && onTap != null) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.touch_app_outlined,
                        size: 11, color: MeshTheme.textSecondary),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ).copyWithGesture(onTap);
  }
}

extension on Widget {
  Widget copyWithGesture(VoidCallback? onTap) {
    if (onTap == null) return this;
    return GestureDetector(onTap: onTap, child: this);
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});
  final TextEditingController controller;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MeshTheme.surface,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(color: MeshTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Сообщение в чат…',
                  hintStyle: const TextStyle(
                    color: MeshTheme.textSecondary,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: MeshTheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onSend,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.send, color: Colors.black, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
