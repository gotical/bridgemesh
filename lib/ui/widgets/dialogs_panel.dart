import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../services/contact_service.dart';
import '../../services/dialogs_service.dart';
import '../../services/identity_service.dart';
import '../../services/routing_service.dart';
import '../../theme/mesh_theme.dart';
import 'chat_panel.dart';

/// Список личных диалогов.
///
/// Личные сообщения — единственная форма чата в приложении.
/// Здесь показывается список собеседников, с которыми у вас была
/// переписка (последнее сообщение + счётчик непрочитанных).
class DialogsPanel extends StatefulWidget {
  const DialogsPanel({
    super.key,
    required this.identity,
    required this.contacts,
    required this.dialogs,
    required this.routing,
  });

  final IdentityService identity;
  final ContactService contacts;
  final DialogsService dialogs;
  final RoutingService routing;

  @override
  State<DialogsPanel> createState() => _DialogsPanelState();
}

class _DialogsPanelState extends State<DialogsPanel> {
  @override
  void initState() {
    super.initState();
    widget.dialogs.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.dialogs.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final list = widget.dialogs.conversations;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: MeshTheme.bgGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(
                count: list.length,
                unread: widget.dialogs.totalUnread,
              ),
              Expanded(
                child: list.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 4),
                        itemBuilder: (ctx, i) {
                          final c = list[i];
                          return _DialogTile(
                            conv: c,
                            onTap: () async {
                              await widget.dialogs.markRead(c.peerId);
                              if (!mounted) return;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChatPanel(
                                    identity: widget.identity,
                                    routing: widget.routing,
                                    contacts: widget.contacts,
                                    dialogs: widget.dialogs,
                                    peerId: c.peerId,
                                    peerName: c.displayName,
                                  ),
                                ),
                              ).then((_) => mounted ? setState(() {}) : null);
                            },
                            onDelete: () =>
                                widget.dialogs.remove(c.peerId),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.unread});
  final int count;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.chat_bubble_outline,
              color: MeshTheme.primary, size: 26),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Диалоги',
              style: TextStyle(
                color: MeshTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: MeshTheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$unread новых',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
              child: const Icon(Icons.forum_outlined,
                  size: 44, color: MeshTheme.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'Тут будут ваши сообщения',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MeshTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Добавьте человека в «Людях» и напишите ему — диалог '
              'появится здесь. Сообщения хранятся локально на вашем '
              'устройстве.',
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

class _DialogTile extends StatelessWidget {
  const _DialogTile({
    required this.conv,
    required this.onTap,
    required this.onDelete,
  });
  final Conversation conv;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final m = conv.lastMessage;
    final preview = m != null
        ? (m.text.isEmpty ? '🔒 зашифровано' : m.text)
        : 'Нет сообщений';
    final time = _formatTime(conv.lastSeen);
    return Container(
      decoration: BoxDecoration(
        color: MeshTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 4,
        ),
        leading: CircleAvatar(
          backgroundColor:
              MeshTheme.primary.withValues(alpha: 0.16),
          child: Text(
            conv.displayName.isNotEmpty
                ? conv.displayName.substring(0, 1).toUpperCase()
                : '?',
            style: const TextStyle(color: MeshTheme.primary),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                conv.displayName,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: MeshTheme.textPrimary,
                  fontWeight: conv.unread > 0
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (m != null && m.isMine == false)
              const Icon(Icons.lock_rounded,
                  size: 14, color: MeshTheme.primary),
          ],
        ),
        subtitle: Text(
          preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: conv.unread > 0
                ? MeshTheme.textPrimary
                : MeshTheme.textSecondary,
            fontWeight: conv.unread > 0
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (time.isNotEmpty)
              Text(
                time,
                style: const TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            const SizedBox(height: 4),
            if (conv.unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: MeshTheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${conv.unread}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        onLongPress: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: MeshTheme.surface,
              title: const Text(
                'Удалить диалог?',
                style: TextStyle(color: MeshTheme.textPrimary),
              ),
              content: Text(
                'Удалить переписку с ${conv.displayName}? '
                'Сообщения исчезнут только у вас.',
                style: const TextStyle(
                    color: MeshTheme.textSecondary, height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Удалить'),
                ),
              ],
            ),
          );
          if (ok == true) onDelete();
        },
      ),
    );
  }

  String _formatTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day);
    final dd = DateTime(d.year, d.month, d.day);
    if (dt == dd) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    if (dt.difference(dd).inDays == 1) {
      return 'вчера';
    }
    return '${d.day}.${d.month.toString().padLeft(2, '0')}';
  }
}
