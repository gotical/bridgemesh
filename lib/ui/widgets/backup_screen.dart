import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/backup_service.dart';
import '../../theme/mesh_theme.dart';
import 'restore_banner.dart';

/// Экран бэкапа: создание / восстановление из зашифрованного
/// бэкапа. Поддерживается передача файлом (через share) или
/// через QR-код (для коротких бэкапов).
class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.backup,
  });

  final BackupService backup;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _newPwdCtrl = TextEditingController();
  final _newPwdCtrl2 = TextEditingController();
  final _restorePwdCtrl = TextEditingController();
  final _restoreTextCtrl = TextEditingController();
  String? _lastBackup;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newPwdCtrl.dispose();
    _newPwdCtrl2.dispose();
    _restorePwdCtrl.dispose();
    _restoreTextCtrl.dispose();
    super.dispose();
  }

  Future<void> _createBackup() async {
    final pwd = _newPwdCtrl.text;
    final pwd2 = _newPwdCtrl2.text;
    if (pwd.length < 4) {
      setState(() => _error = 'Пароль слишком короткий (мин. 4 символа)');
      return;
    }
    if (pwd != pwd2) {
      setState(() => _error = 'Пароли не совпадают');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = await widget.backup.createBackup(pwd);
      setState(() {
        _lastBackup = payload;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _shareBackup() async {
    final p = _lastBackup;
    if (p == null) return;
    // Сохраняем в формате, пригодном для бэкапа.
    await Share.share(
      p,
      subject: 'BridgeMesh бэкап',
    );
  }

  Future<void> _restore() async {
    final txt = _restoreTextCtrl.text.trim();
    final pwd = _restorePwdCtrl.text;
    if (txt.isEmpty || pwd.isEmpty) {
      setState(() => _error = 'Введите бэкап и пароль');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await widget.backup.restoreBackup(txt, pwd);
      if (!mounted) return;
      // Покажем краткое подтверждение.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isForeignDevice
                ? 'Бэкап с узла «${result.originAlias}» '
                    'восстановлен. Это другое устройство.'
                : 'Бэкап восстановлен',
          ),
        ),
      );
      // Покажем баннер «восстановлено».
      await showDialog(
        context: context,
        builder: (_) => RestoredBanner(
          originAlias: result.originAlias,
          originNodeId: result.originNodeId,
          onDismiss: () => Navigator.pop(context),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: MeshTheme.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _appBar(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _sectionTitle(
                      'Создать бэкап',
                      icon: Icons.lock_outline,
                    ),
                    const SizedBox(height: 8),
                    _passwordField(_newPwdCtrl, 'Пароль'),
                    const SizedBox(height: 8),
                    _passwordField(_newPwdCtrl2, 'Повторите пароль'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _createBackup,
                        icon: const Icon(Icons.save),
                        label: const Text('Создать зашифрованный бэкап'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MeshTheme.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    if (_lastBackup != null) ...[
                      const SizedBox(height: 12),
                      _qrPreview(_lastBackup!),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _shareBackup,
                        icon: const Icon(Icons.share),
                        label: const Text('Поделиться бэкапом'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MeshTheme.secondary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _lastBackup!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Бэкап скопирован в буфер обмена'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Скопировать текст бэкапа'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: MeshTheme.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: MeshTheme.danger.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: MeshTheme.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 8),
                    _sectionTitle(
                      'Восстановить из бэкапа',
                      icon: Icons.restore,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _restoreTextCtrl,
                      maxLines: 4,
                      style: const TextStyle(
                        color: MeshTheme.textPrimary,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                      decoration: _inputDeco(
                        'Вставьте текст бэкапа (bmBackup:v1:...)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    _passwordField(_restorePwdCtrl, 'Пароль бэкапа'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _restore,
                        icon: const Icon(Icons.download),
                        label: const Text('Восстановить'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MeshTheme.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MeshTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: MeshTheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined,
                              color: MeshTheme.primary, size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Бэкап шифруется AES-256 вашим паролем. '
                              'Пароль НЕ сохраняется в файле — его '
                              'нужно будет ввести при восстановлении. '
                              'Если вы восстановите бэкап на другом '
                              'устройстве, появится предупреждение.',
                              style: TextStyle(
                                color: MeshTheme.textSecondary,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: MeshTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'Бэкап',
            style: TextStyle(
              color: MeshTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t, {required IconData icon}) {
    return Row(
      children: [
        Icon(icon, color: MeshTheme.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          t,
          style: const TextStyle(
            color: MeshTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _passwordField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      obscureText: true,
      style: const TextStyle(color: MeshTheme.textPrimary),
      decoration: _inputDeco(label),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: MeshTheme.textSecondary),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  Widget _qrPreview(String data) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final size = c.maxWidth.clamp(180.0, 280.0);
          return Center(
            child: SizedBox(
              width: size,
              height: size,
              child: QrImageView(
                data: data,
                version: QrVersions.auto,
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
          );
        },
      ),
    );
  }
}
