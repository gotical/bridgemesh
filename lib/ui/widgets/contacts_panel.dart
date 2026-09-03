import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/contact.dart';
import '../../services/contact_service.dart';
import '../../services/identity_service.dart';
import '../../services/routing_service.dart';
import '../../theme/mesh_theme.dart';

class ContactsPanel extends StatefulWidget {
  const ContactsPanel({
    super.key,
    required this.identity,
    required this.contacts,
    required this.routing,
  });

  final IdentityService identity;
  final ContactService contacts;
  final RoutingService routing;

  @override
  State<ContactsPanel> createState() => _ContactsPanelState();
}

class _ContactsPanelState extends State<ContactsPanel> {
  @override
  void initState() {
    super.initState();
    widget.contacts.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.contacts.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  /// Содержимое QR-кода и share-строки — компактная ссылка,
  /// содержащая nodeId, alias и группу. Это «внутренняя ссылка
  /// BridgeMesh», не использующая интернет.
  String _myShareText() {
    return 'bridgemesh://contact'
        '?id=${widget.identity.nodeId}'
        '&alias=${Uri.encodeComponent(widget.identity.alias)}'
        '&group=${Uri.encodeComponent(widget.identity.groupId)}'
        '&v=1';
  }

  Future<void> _shareDeepLink() async {
    await Share.share(
      _myShareText(),
      subject: 'BridgeMesh — мой контакт',
    );
  }

  /// Ручное добавление: пользователь вводит Node ID другого
  /// участника (например, после того, как ему продиктовали
  /// короткий код AB12-3C4D). Это рабочая альтернатива
  /// камерному сканеру, который в меш-сети часто недоступен.
  Future<void> _enterContactCode() async {
    final ctl = TextEditingController();
    final aliasCtl = TextEditingController();
    final result = await showDialog<Contact>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: MeshTheme.surface,
        title: const Text(
          'Добавить контакт',
          style: TextStyle(color: MeshTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Введите идентификатор, который вам продиктовал '
              'другой участник (например, AB12-3C4D). Можно ввести '
              'только короткий код или полный.',
              style: TextStyle(color: MeshTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              style: const TextStyle(
                color: MeshTheme.textPrimary,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                hintText: 'AB12-3C4D5E6F...',
                prefixIcon: Icon(Icons.tag),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: aliasCtl,
              style: const TextStyle(color: MeshTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Имя (необязательно)',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final raw = ctl.text.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
              if (raw.isEmpty) return;
              final alias = aliasCtl.text.trim().isEmpty
                  ? raw.substring(0, raw.length >= 4 ? 4 : raw.length)
                  : aliasCtl.text.trim();
              Navigator.pop(
                context,
                Contact(
                  nodeId: raw.toUpperCase().padRight(16, '0').substring(0, 16),
                  alias: alias,
                  addedAt: DateTime.now().millisecondsSinceEpoch,
                  lastSeen: DateTime.now().millisecondsSinceEpoch,
                ),
              );
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (result != null) {
      await widget.contacts.addContact(result.nodeId, note: 'Введён вручную');
      // Также применим alias, если введён.
      if (result.alias.isNotEmpty && result.alias != result.nodeId.substring(0, 4)) {
        // Локально меняем алиас, отправив свою визитку с этим именем.
        // Для чужого контакта это ничего не делает.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Добавлен контакт ${result.alias} '
              '(${result.shortId})'),
        ),
      );
    }
  }

  void _handleDeepLink(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'bridgemesh') return;
      final id = uri.queryParameters['id'] ?? '';
      final alias = uri.queryParameters['alias'] ?? id;
      if (id.isEmpty) return;
      widget.contacts.addContact(id, note: 'QR / share');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Добавлен контакт $alias (${id.substring(0, 4)}…)'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось разобрать ссылку: $e')),
      );
    }
  }

  Future<void> _broadcastCard() async {
    await widget.routing.sendContactCard();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Визитка разослана в mesh')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.contacts.contacts;
    final requests = widget.contacts.pendingRequests;
    final learned = widget.contacts.learned.toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MyCard(
          identity: widget.identity,
          shareText: _myShareText(),
          onShare: _shareDeepLink,
          onEnter: _enterContactCode,
          onBroadcast: _broadcastCard,
        ),
        const SizedBox(height: 16),
        if (requests.isNotEmpty) ...[
          const _SectionHeader(
            title: 'Запросы на добавление',
            icon: Icons.mail_outline,
          ),
          ...requests.map((c) => _RequestCard(
                contact: c,
                onAccept: () => widget.contacts.acceptRequest(c.nodeId),
                onReject: () => widget.contacts.rejectRequest(c.nodeId),
              )),
          const SizedBox(height: 16),
        ],
        _SectionHeader(
          title: 'Мои контакты',
          icon: Icons.people_outline,
          count: all.length,
        ),
        if (all.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Пока нет добавленных контактов.\nПокажите свой QR или '
              'введите Node ID нового участника вручную.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MeshTheme.textSecondary),
            ),
          )
        else
          ...all.map((c) => _ContactTile(
                contact: c,
                onTap: () => _showHistory(c),
                onRemove: () => widget.contacts.removeContact(c.nodeId),
              )),
        if (learned.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionHeader(
            title: 'Видел в mesh',
            icon: Icons.visibility_outlined,
            count: learned.length,
          ),
          ...learned.map(
            (c) => _LearnedTile(
              contact: c,
              onAdd: () => widget.contacts.addContact(c.nodeId),
            ),
          ),
        ],
      ],
    );
  }

  void _showHistory(Contact c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: MeshTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _HistorySheet(contact: c),
    );
  }
}

class _MyCard extends StatelessWidget {
  const _MyCard({
    required this.identity,
    required this.shareText,
    required this.onShare,
    required this.onEnter,
    required this.onBroadcast,
  });

  final IdentityService identity;
  final String shareText;
  final VoidCallback onShare;
  final VoidCallback onEnter;
  final VoidCallback onBroadcast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MeshTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Моя визитка',
            style: TextStyle(
              color: MeshTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                identity.shortNodeId,
                style: const TextStyle(
                  color: MeshTheme.primary,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.copy_all_rounded,
                  size: 16,
                  color: MeshTheme.textSecondary,
                ),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: identity.nodeId));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Node ID скопирован')),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: shareText,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Имя: ${identity.alias}',
            style: const TextStyle(
              color: MeshTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            'ID: ${identity.shortNodeId}',
            style: const TextStyle(
              color: MeshTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onEnter,
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Ввести код'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MeshTheme.surfaceAlt,
                    foregroundColor: MeshTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share),
                  label: const Text('Поделиться'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: onBroadcast,
            icon: const Icon(Icons.podcasts),
            label: const Text('Разослать визитку в mesh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MeshTheme.secondary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    this.count,
  });
  final String title;
  final IconData icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: MeshTheme.primary, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: MeshTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: MeshTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: MeshTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.contact,
    required this.onAccept,
    required this.onReject,
  });
  final Contact contact;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MeshTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MeshTheme.secondary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.alias,
                  style: const TextStyle(
                    color: MeshTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  contact.shortId,
                  style: const TextStyle(
                    color: MeshTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle, color: MeshTheme.success),
            onPressed: onAccept,
            tooltip: 'Принять',
          ),
          IconButton(
            icon: const Icon(Icons.cancel, color: MeshTheme.danger),
            onPressed: onReject,
            tooltip: 'Отклонить',
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.onTap,
    required this.onRemove,
  });
  final Contact contact;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: MeshTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor:
                  MeshTheme.primary.withValues(alpha: 0.15),
              child: Text(
                contact.alias.isNotEmpty
                    ? contact.alias.substring(0, 1).toUpperCase()
                    : '?',
                style: const TextStyle(color: MeshTheme.primary),
              ),
            ),
            if (contact.online)
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
        title: Text(
          contact.alias,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: const TextStyle(
            color: MeshTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Row(
          children: [
            Flexible(
              child: Text(
                contact.shortId,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (contact.mutual) ...[
              const SizedBox(width: 6),
              const Icon(Icons.handshake,
                  size: 12, color: MeshTheme.secondary),
              const SizedBox(width: 2),
              const Text(
                'взаимно',
                style: TextStyle(
                  color: MeshTheme.secondary,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: MeshTheme.danger),
          onPressed: onRemove,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _LearnedTile extends StatelessWidget {
  const _LearnedTile({required this.contact, required this.onAdd});
  final Contact contact;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MeshTheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: MeshTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.alias,
                  style: const TextStyle(color: MeshTheme.textPrimary),
                ),
                Text(
                  contact.shortId,
                  style: const TextStyle(
                    color: MeshTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: const Text('Добавить'),
          ),
        ],
      ),
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final entries = contact.aliasHistory.reversed.toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scroll) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              contact.alias,
              style: const TextStyle(
                color: MeshTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              contact.nodeId,
              style: const TextStyle(
                color: MeshTheme.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'История имён',
              style: TextStyle(
                color: MeshTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: entries.length,
                itemBuilder: (_, i) {
                  final e = entries[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.label_outline,
                        color: MeshTheme.primary),
                    title: Text(
                      e.alias,
                      style: const TextStyle(color: MeshTheme.textPrimary),
                    ),
                    subtitle: Text(
                      _formatDate(e.since),
                      style: const TextStyle(
                        color: MeshTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}
