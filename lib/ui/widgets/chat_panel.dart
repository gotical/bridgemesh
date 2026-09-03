import 'package:flutter/material.dart';

import 'animated_card.dart';
import 'package:intl/intl.dart';

import '../../services/contact_service.dart';
import '../../services/identity_service.dart';
import '../../services/routing_service.dart';
import '../../theme/mesh_theme.dart';
import '../../models/chat_message.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.identity,
    required this.routing,
    required this.contacts,
  });

  final IdentityService identity;
  final RoutingService routing;
  final ContactService contacts;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.routing.addListener(_onRoutingChange);
    widget.contacts.addListener(_onRoutingChange);
  }

  @override
  void dispose() {
    widget.routing.removeListener(_onRoutingChange);
    widget.contacts.removeListener(_onRoutingChange);
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onRoutingChange() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty) return;
    _ctrl.clear();
    await widget.routing.sendText(txt);
  }

  Future<void> _sos() async {
    final txt = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: MeshTheme.surface,
        title: const Text(
          'SOS-сигнал',
          style: TextStyle(color: MeshTheme.textPrimary),
        ),
        content: const Text(
          'Текст SOS будет ретранслирован каждым узлом, пока не дойдёт '
          'до адресата. Используйте только в реальной чрезвычайной ситуации.',
          style: TextStyle(color: MeshTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'Нужна помощь'),
            child: const Text(
              'Отправить SOS',
              style: TextStyle(color: MeshTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (txt != null) {
      await widget.routing.sendSos(txt);
    }
  }

  Future<void> _addToContacts(ChatMessage m) async {
    // У P2P-сообщений нет nodeId — для личных сообщений имя контакта = alias.
    await widget.contacts.addContact(
      m.from,
      note: 'Из личного чата',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${m.from} добавлен в контакты')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.routing.messages;
    return Column(
      children: [
        Expanded(
          child: msgs.isEmpty
              ? const _Empty()
              : ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final msg = msgs[i];
                    final c = widget.contacts.byId(msg.from);
                    final isContact = c != null;
                    return FadeInItem(
                      key: ValueKey(msg.id),
                      delay: Duration(milliseconds: 40 * (i < 5 ? i : 5)),
                      child: _Bubble(
                        msg: msg,
                        isContact: isContact && !msg.isMine,
                        onAddContact: !msg.isMine
                            ? () => _addToContacts(msg)
                            : null,
                      ),
                    );
                  },
                ),
        ),
        _Composer(
          controller: _ctrl,
          onSend: _send,
          onSos: _sos,
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cell_tower,
              size: 56,
              color: MeshTheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Тишина в эфире',
              style: TextStyle(
                color: MeshTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Личные сообщения. Любой узел может прочитать их, если\n'
              'знает ваш ID или display-имя. Имена отправителей\n'
              'можно добавить в контакты в один клик.',
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
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.msg,
    required this.isContact,
    this.onAddContact,
  });
  final ChatMessage msg;
  final bool isContact;
  final VoidCallback? onAddContact;

  @override
  Widget build(BuildContext context) {
    final isMine = msg.isMine;
    final scheme = Theme.of(context).colorScheme;
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      msg.from,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MeshTheme.secondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.lock_rounded,
                    size: 11,
                    color: MeshTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  if (isContact)
                    const Icon(Icons.check_circle,
                        size: 12, color: MeshTheme.success)
                  else if (onAddContact != null)
                    InkWell(
                      onTap: onAddContact,
                      child: const Icon(
                        Icons.person_add_alt_1,
                        size: 14,
                        color: MeshTheme.primary,
                      ),
                    ),
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
                    color: isMine
                        ? Colors.black54
                        : MeshTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 6),
                if (isMine) ...[
                  if (msg.hops > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '${msg.hops} hop',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  Icon(
                    msg.statusIcon(),
                    size: 12,
                    color: isMine
                        ? Colors.black54
                        : msg.statusColor(scheme),
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
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onSos,
  });
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onSos;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: onSos,
            icon: const Icon(Icons.emergency_rounded),
            color: MeshTheme.danger,
            tooltip: 'SOS',
            style: IconButton.styleFrom(
              backgroundColor: MeshTheme.danger.withValues(alpha: 0.1),
            ),
          ),
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
                  hintText: 'Личное сообщение...',
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
