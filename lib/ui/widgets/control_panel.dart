import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/contact_service.dart';
import '../../services/geo_service.dart';
import '../../services/identity_service.dart';
import '../../services/message_store.dart';
import '../../services/backup_service.dart';
import '../../services/routing_service.dart';
import '../../services/transport_bluetooth.dart';
import '../../services/transport_wifi_direct.dart';
import '../../services/power_mode.dart';
import '../../theme/mesh_theme.dart';
import 'about_screen.dart';
import 'backup_screen.dart';

class ControlPanel extends StatefulWidget {
  const ControlPanel({
    super.key,
    required this.identity,
    required this.routing,
    required this.bluetooth,
    required this.wifi,
    required this.geo,
    required this.contacts,
    required this.store,
    required this.backup,
    required this.power,
  });

  final IdentityService identity;
  final RoutingService routing;
  final BluetoothTransport bluetooth;
  final WifiDirectTransport wifi;
  final GeoService geo;
  final ContactService contacts;
  final MessageStore store;
  final BackupService backup;
  final PowerModeService power;

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  final _idCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    widget.routing.addListener(_onChange);
    widget.power.addListener(_onChange);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    widget.routing.removeListener(_onChange);
    widget.power.removeListener(_onChange);
    _refreshTimer?.cancel();
    _idCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  void _onChange() => setState(() {});

  Future<void> _directMessage() async {
    final to = _idCtrl.text.trim();
    final msg = _msgCtrl.text.trim();
    if (to.isEmpty || msg.isEmpty) return;
    await widget.routing.sendText(msg, to: to);
    _msgCtrl.clear();
  }

  Future<void> _renameAlias() async {
    final ctl = TextEditingController(text: widget.identity.alias);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: MeshTheme.surface,
        title: const Text(
          'Новое имя',
          style: TextStyle(color: MeshTheme.textPrimary),
        ),
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: const TextStyle(color: MeshTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (ok == true && ctl.text.trim().isNotEmpty) {
      await widget.identity.setAlias(ctl.text.trim());
      await widget.routing.sendContactCard();
      if (mounted) setState(() {});
    }
  }

  Future<bool?> _confirmEconomy(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: MeshTheme.surface,
        title: const Text(
          'Отключиться?',
          style: TextStyle(color: MeshTheme.textPrimary),
        ),
        content: const Text(
          'Приложение уйдёт в эконом-режим:\n\n'
          '• Bluetooth сканирует раз в минуту.\n'
          '• Wi-Fi не вещает (только слушает).\n'
          '• Вы остаётесь посредником — пропускаете '
          'сообщения через себя, когда телефон ненадолго '
          'просыпается.\n\n'
          'Заряд тратится в 5–10 раз меньше. Соседи будут '
          'видеть вас реже. Чтобы снова стать «видимым» — '
          'верните обычный режим.',
          style: TextStyle(color: MeshTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: MeshTheme.success,
              foregroundColor: Colors.black,
            ),
            child: const Text('Отключиться'),
          ),
        ],
      ),
    );
  }

  Future<void> _setPhone() async {
    final ctl = TextEditingController(text: widget.identity.phone);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: MeshTheme.surface,
        title: const Text(
          'Номер телефона',
          style: TextStyle(color: MeshTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: MeshTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: '+7 999 123-45-67',
                hintStyle: TextStyle(color: MeshTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Номер никуда не отправляется на сервер. '
              'Он используется, чтобы собеседник увидел ваше имя '
              'из своей записной книжки.',
              style: TextStyle(
                color: MeshTheme.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.identity.setPhone(ctl.text.trim());
      await widget.routing.sendContactCard();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TransportCard(
          title: 'Bluetooth',
          icon: Icons.bluetooth,
          enabled: widget.bluetooth.isRunning,
          description:
              'Передача данных по Bluetooth LE. Радиус 30–100 м, '
              'работает даже без роутера и Wi-Fi.',
        ),
        const SizedBox(height: 12),
        _TransportCard(
          title: 'Wi-Fi',
          icon: Icons.wifi_tethering,
          enabled: widget.wifi.isRunning,
          description:
              'Wi-Fi Direct (точка-точка) или общая сеть. Радиус '
              '50–200 м, высокая скорость.',
        ),
        const SizedBox(height: 16),

        // === Режим работы (эконом / обычный) ===
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _box(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.power.isEconomy
                        ? Icons.battery_saver
                        : Icons.flash_on,
                    color: widget.power.isEconomy
                        ? MeshTheme.success
                        : MeshTheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Режим работы',
                      style: TextStyle(
                        color: MeshTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: widget.power.isEconomy,
                    activeColor: MeshTheme.success,
                    onChanged: (v) async {
                      await widget.power.set(
                        v ? PowerMode.economy : PowerMode.normal,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(v
                              ? 'Эконом-режим включён. Вы — посредник, '
                                  'но сканирование редкое.'
                              : 'Обычный режим. Сообщения идут чаще.'),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                      setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.power.isEconomy
                    ? 'Радио просыпается раз в минуту. Вы остаётесь '
                        'посредником: принимаете и передаёте сообщения, '
                        'когда телефон ненадолго включается, чтобы '
                        'проверить соседей. Заряд тратится в 5–10 раз '
                        'меньше, чем в обычном режиме.'
                    : 'Обычный режим. Ищет соседей постоянно, чтобы '
                        'сообщения шли быстрее. Тратит заметно больше '
                        'заряда.',
                style: const TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.power.isEconomy)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await widget.power.set(PowerMode.normal);
                      if (!mounted) return;
                      setState(() {});
                    },
                    icon: const Icon(Icons.flash_on, size: 18),
                    label: const Text('Включить обычный режим'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MeshTheme.primary,
                      side: const BorderSide(color: MeshTheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final ok = await _confirmEconomy(context);
                      if (ok == true) {
                        await widget.power.set(PowerMode.economy);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Эконом-режим. Заряд почти не тратится, '
                              'но вас реже находят.',
                            ),
                            duration: Duration(seconds: 3),
                          ),
                        );
                        setState(() {});
                      }
                    },
                    icon: const Icon(Icons.battery_saver, size: 18),
                    label: const Text('Отключиться (эконом)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MeshTheme.success.withValues(alpha: 0.15),
                      foregroundColor: MeshTheme.success,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _box(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Мой профиль',
                      style: TextStyle(
                        color: MeshTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _renameAlias,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Сменить имя'),
                  ),
                  TextButton.icon(
                    onPressed: _setPhone,
                    icon: const Icon(Icons.phone_outlined, size: 16),
                    label: Text(
                      widget.identity.phone.isEmpty
                          ? 'Указать телефон'
                          : 'Телефон',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _kv('Имя', widget.identity.alias),
              _kv('Идентификатор', widget.identity.shortNodeId),
              if (widget.identity.phone.isNotEmpty)
                _kv('Телефон', '+${widget.identity.phone}'),
              _kv('Имя изменилось раз', widget.identity.aliasHistory.length.toString()),
              const SizedBox(height: 8),
              const Text(
                'Идентификатор — это короткий код, который видят другие. '
                'Делитесь им вслух — собеседник вводит его у себя в '
                '«Людях». Имя можно менять — история хранится.',
                style: TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _box(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Текущая локация',
                style: TextStyle(
                  color: MeshTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              _kv('Город', widget.geo.currentCityName),
              _kv('Slug', widget.geo.currentCitySlug),
              if (widget.geo.position != null)
                _kv(
                  'Координаты',
                  '${widget.geo.position!.latitude.toStringAsFixed(4)}, '
                      '${widget.geo.position!.longitude.toStringAsFixed(4)}',
                ),
              const SizedBox(height: 8),
              const Text(
                'Mesh автоматически создаёт комнату с названием '
                'ближайшего города по GPS. Сообщения, которые вы пишете, '
                'копируются и попадают к другим узлам в этом городе.',
                style: TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _box(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Прямое сообщение узлу',
                style: TextStyle(
                  color: MeshTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Отправляется адресно через всю меш-сеть.',
                style: TextStyle(color: MeshTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _idCtrl,
                style: const TextStyle(color: MeshTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Имя узла получателя',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _msgCtrl,
                style: const TextStyle(color: MeshTheme.textPrimary),
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Текст сообщения',
                  prefixIcon: Icon(Icons.message_outlined),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _directMessage,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Отправить адресно'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _box(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Как работает BridgeMesh',
                style: TextStyle(
                  color: MeshTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Mesh-сеть не требует интернета, сотовых вышек или '
                'выделенных серверов.\n'
                '• Каждый узел — одновременно клиент, ретранслятор и точка '
                'обнаружения. Чем больше людей с приложением, тем выше шанс '
                'доставки.\n'
                '• Контакты добавляются через QR, share-ссылку или после '
                'встречи «в эфире». Визитка обновляется автоматически.\n'
                '• Городские чаты работают через GPS: каждый пишет в '
                'комнату своего города, узлы обмениваются «снимками» при встрече.\n'
                '• HMAC-SHA256 подпись пакета — никто не выдаёт себя за вас.\n'
                '• Пакеты идут по BLE / Wi-Fi Direct / UDP / TCP — все '
                'беспроводные протоколы, которые есть в устройстве.',
                style: TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: widget.identity.nodeId),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Идентификатор скопирован')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_all_rounded),
                label: const Text('Скопировать ID'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MeshTheme.secondary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  widget.routing.start();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mesh перезапущен')),
                  );
                },
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Перезапуск'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MeshTheme.surfaceAlt,
                  foregroundColor: MeshTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _box(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ретрансляция в mesh',
                style: TextStyle(
                  color: MeshTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Этот узел хранит копии пакетов и повторно передаёт их '
                'встречным узлам — даже если вы сами давно прочли '
                'сообщение. Это сильно повышает шанс доставки.',
                style: TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              _kv('Для адресатов', widget.store.pendingForOthers.toString()),
              _kv('Для всех', widget.store.pendingBroadcast.toString()),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MeshTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: MeshTheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lock_rounded,
                      color: MeshTheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Личные сообщения хранятся в зашифрованном '
                        'виде. Этот узел не может прочитать текст '
                        '— только отправитель и конечный адресат '
                        'имеют общий ключ. Посредник просто '
                        'передаёт блоб дальше по цепочке.',
                        style: TextStyle(
                          color: MeshTheme.textPrimary,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AboutScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Подробнее'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MeshTheme.primary,
                        side: const BorderSide(color: MeshTheme.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _box(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Бэкап',
                style: TextStyle(
                  color: MeshTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Сохраните контакты и чаты в зашифрованном файле '
                'или QR-коде. Пароль придумайте сами — он не '
                'передаётся на сервер.',
                style: TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BackupScreen(
                              backup: widget.backup,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Бэкап'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MeshTheme.primary,
                        side: const BorderSide(color: MeshTheme.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _box(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Поделиться приложением',
                style: TextStyle(
                  color: MeshTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Чем больше людей с BridgeMesh — тем выше шанс доставки. '
                'Передайте APK через Bluetooth или системный share.',
                style: TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _shareApkIntent,
                icon: const Icon(Icons.share),
                label: const Text('Поделиться через системное меню'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MeshTheme.secondary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Совет: отправляйте APK через Bluetooth-файлообмен или '
                'через любой оффлайн-канал (NFC, флешка, QR-ссылка). '
                'На телефоне получателя файл нужно открыть и разрешить '
                'установку из неизвестных источников.',
                style: TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Future<void> _shareApkIntent() async {
    // Прямой системный share: обычно BridgeMesh будет
    // передаваться через любой мессенджер / Bluetooth.
    // Само приложение не имеет доступа к своему APK в debug-режиме,
    // но пользователь может скопировать его вручную или скачать
    // через share-диалог.
    final link = 'https://rybinsklab.ru/bridgemesh';
    await Share.share(
      'Установи BridgeMesh — мессенджер, который работает даже без '
      'интернета и сотовой связи. Приложение создаёт mesh-сеть через '
      'Bluetooth и Wi-Fi Direct.\n\n$link',
      subject: 'BridgeMesh — меш-сеть без интернета',
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              child: Text(
                k,
                style: const TextStyle(
                  color: MeshTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Text(
                v,
                style: const TextStyle(
                  color: MeshTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  BoxDecoration _box() => BoxDecoration(
        color: MeshTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      );
}

class _TransportCard extends StatelessWidget {
  const _TransportCard({
    required this.title,
    required this.icon,
    required this.enabled,
    required this.description,
  });
  final String title;
  final IconData icon;
  final bool enabled;
  final String description;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? MeshTheme.success : MeshTheme.danger;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MeshTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MeshTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        enabled ? 'АКТИВЕН' : 'ВЫКЛ',
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: MeshTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
