import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'animated_card.dart';

import '../../services/contact_service.dart';
import '../../services/dialogs_service.dart';
import '../../services/identity_service.dart';
import '../../services/routing_service.dart';
import '../../theme/mesh_theme.dart';
import '../../models/chat_message.dart';

/// Личный чат 1-на-1.
///
/// Если `peerId == null` — показывает пустое состояние
/// (открывать нужно через DialogsPanel или карточку контакта).
class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.identity,
    required this.routing,
    required this.contacts,
    required this.dialogs,
    this.peerId,
    this.peerName,
  });

  final IdentityService identity;
  final RoutingService routing;
  final ContactService contacts;
  final DialogsService dialogs;
  final String? peerId;
  final String? peerName;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.routing.addListener(_onChange);
    widget.contacts.addListener(_onChange);
    widget.dialogs.addListener(_onChange);
    if (widget.peerId != null) {
      // открыли диалог — сразу сбрасываем счётчик непрочитанных
      widget.dialogs.markRead(widget.peerId!);
    }
  }

  @override
  void dispose() {
    widget.routing.removeListener(_onChange);
    widget.contacts.removeListener(_onChange);
    widget.dialogs.removeListener(_onChange);
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
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
    if (txt.isEmpty || widget.peerId == null) return;
    _ctrl.clear();
    await widget.routing.sendText(txt, to: widget.peerId);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.peerId == null) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: MeshTheme.bgGradient),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 56, color: MeshTheme.primary),
                  SizedBox(height: 12),
                  Text(
                    'Личные сообщения',
                    style: TextStyle(
                      color: MeshTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Выберите человека в «Диалогах», чтобы написать. '
                    'Переписка шифруется, никто кроме собеседника '
                    'не видит текст.',
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
          ),
        ),
      );
    }

    final msgs = widget.dialogs.messagesWith(widget.peerId!);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: MeshTheme.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                title: widget.peerName ?? widget.peerId!,
                onBack: () => Navigator.of(context).maybePop(),
                onSos: () => _sos(context),
              ),
              Expanded(
                child: msgs.isEmpty
                    ? _EmptyDialog(peer: widget.peerName ?? widget.peerId!)
                    : ListView.builder(
                        controller: _scrollCtrl,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        itemCount: msgs.length,
                        itemBuilder: (ctx, i) {
                          final m = msgs[msgs.length - 1 - i];
                          return _Bubble(msg: m);
                        },
                      ),
              ),
              _Composer(ctrl: _ctrl, onSend: _send),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sos(BuildContext context) async {
    final txt = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: MeshTheme.surface,
        title: const Text(
          'SOS-сигнал',
          style: TextStyle(color: MeshTheme.textPrimary),
        ),
        content: const Text(
          'Сигнал будет разослан всем узлам поблизости с вашим '
          'местоположением. Используйте в реальной чрезвычайной '
          'ситуации.',
          style: TextStyle(color: MeshTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'Нужна помощь'),
            child: const Text(
              'Отправить',
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
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onBack,
    required this.onSos,
  });
  final String title;
  final VoidCallback onBack;
  final VoidCallback onSos;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: MeshTheme.textPrimary),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                    color: MeshTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.lock_rounded, size: 12, color: MeshTheme.primary),
                    SizedBox(width: 4),
                    Text(
                      'Шифрованный диалог',
                      style: TextStyle(
                        color: MeshTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded,
                color: MeshTheme.danger),
            tooltip: 'SOS',
            onPressed: onSos,
          ),
        ],
      ),
    );
  }
}

class _EmptyDialog extends StatelessWidget {
  const _EmptyDialog({required this.peer});
  final String peer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, size: 56, color: MeshTheme.primary),
            const SizedBox(height: 12),
            Text(
              'Диалог с $peer',
              style: const TextStyle(
                color: MeshTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Сообщения шифруются. Никто, кроме собеседника, '
              'не увидит текст — даже посредники в mesh-сети.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MeshTheme.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});
  final ChatMessage msg;

  @override
  Widget build(BuildContext context) {
    final isMine = msg.isMine;
    final time = DateFormat('HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
    );
    return FadeInItem(
      delay: const Duration(milliseconds: 30),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMine ? MeshTheme.primary : MeshTheme.surface,
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
              mainAxisSize: MainAxisSize.min,
              children: [
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
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      Icon(msg.statusIcon(), size: 11, color: Colors.black54),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.ctrl, required this.onSend});
  final TextEditingController ctrl;
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
                controller: ctrl,
                minLines: 1,
                maxLines: 5,
                style: const TextStyle(color: MeshTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Сообщение…',
                  hintStyle: const TextStyle(color: MeshTheme.textSecondary),
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
