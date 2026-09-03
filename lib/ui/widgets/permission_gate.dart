import 'package:flutter/material.dart';

import '../../services/identity_service.dart';
import '../../theme/mesh_theme.dart';

/// Приветственный экран — пользователь вводит имя и по желанию
/// номер телефона (для сверки с записной книжкой).
class PermissionGate extends StatefulWidget {
  const PermissionGate({
    super.key,
    required this.identity,
    required this.onGranted,
    required this.builder,
  });

  final IdentityService identity;
  final VoidCallback onGranted;
  final WidgetBuilder builder;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool _granted = false;
  final _aliasCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _aliasCtrl.text = widget.identity.alias;
    _phoneCtrl.text = widget.identity.phone;
    // Если данные уже сохранены — пропускаем приветственный экран.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trySkip();
    });
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _phoneCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _trySkip() async {
    if (!mounted) return;
    // Если IdentityService ещё не загрузился — подождём.
    for (var i = 0; i < 30; i++) {
      if (widget.identity.isReady) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    if (widget.identity.isOnboarded) {
      setState(() {
        _booting = false;
        _granted = true;
      });
      widget.onGranted();
    } else {
      setState(() => _booting = false);
    }
  }

  Future<void> _enter() async {
    await widget.identity.setAlias(_aliasCtrl.text);
    await widget.identity.setPhone(_phoneCtrl.text);
    if (!mounted) return;
    setState(() => _granted = true);
    widget.onGranted();
  }

  List<Widget> _howItWorks() {
    return const [
      _Step(
        n: '1',
        icon: Icons.podcasts,
        title: 'Видит людей рядом',
        body: 'Находит людей с BridgeMesh поблизости через Bluetooth и Wi-Fi.',
      ),
      _Step(
        n: '2',
        icon: Icons.shield_outlined,
        title: 'Передаёт через других',
        body: 'Сообщения идут через посредников — даже если адресат далеко.',
      ),
      _Step(
        n: '3',
        icon: Icons.mark_chat_read,
        title: 'Достигает адресата',
        body: 'Сообщение хранится у встречных людей, пока не дойдёт до цели.',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_granted) return Builder(builder: widget.builder);

    if (_booting) {
      // Пока данные загружаются — короткий экран «загрузка».
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: MeshTheme.bgGradient),
          child: const Center(
            child: SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(color: MeshTheme.primary),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: MeshTheme.bgGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 56,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: MeshTheme.headerGradient,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    MeshTheme.primary.withValues(alpha: 0.5),
                                blurRadius: 32,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.hub_rounded,
                            size: 44,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'BridgeMesh',
                          style: TextStyle(
                            color: MeshTheme.textPrimary,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Сеть, в которой люди соединяют людей — без '
                          'интернета, без сотовых вышек, без цензуры.',
                          style: TextStyle(
                            color: MeshTheme.textSecondary,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 18),
                        ..._howItWorks().expand(
                          (w) => [w, const SizedBox(height: 8)],
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Как вас увидят другие',
                          style: TextStyle(
                            color: MeshTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: _aliasCtrl,
                          label: 'Ваше имя (например, Алексей)',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: _phoneCtrl,
                          label:
                              'Номер телефона (необязательно, для удобства)',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: MeshTheme.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: MeshTheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.lightbulb_outline,
                                  color: MeshTheme.primary, size: 18),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Имя можно изменить в любой момент. '
                                  'Если ввести номер, собеседники увидят '
                                  'ваше имя из своих контактов — даже '
                                  'если оно отличается от того, что '
                                  'вы ввели здесь.',
                                  style: TextStyle(
                                    color: MeshTheme.textSecondary,
                                    fontSize: 12,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _enter,
                            icon: const Icon(Icons.bolt_rounded),
                            label: const Text('Начать общение'),
                            style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: MeshTheme.primary,
                              foregroundColor: Colors.black,
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Center(
                          child: Text(
                            'Bluetooth · Wi-Fi · Соседи рядом\n'
                            'без интернета и сотовой связи',
                            textAlign: TextAlign.center,
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
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: MeshTheme.textPrimary),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: MeshTheme.primary),
          hintText: label,
          hintStyle: const TextStyle(
            color: MeshTheme.textSecondary,
            fontSize: 14,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: MeshTheme.primary),
          ),
          filled: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.icon,
    required this.title,
    required this.body,
  });
  final String n;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: MeshTheme.headerGradient,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: Colors.black),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MeshTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  body,
                  style: const TextStyle(
                    color: MeshTheme.textSecondary,
                    fontSize: 11,
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
