import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/mesh_theme.dart';

/// Экран «О приложении».
///
/// Содержит:
///  • Историю BridgeMesh — зачем создано.
///  • Информацию о разработчике (RybinskLab, г. Рыбинск).
///  • Подробные рекомендации для пользователей: как ускорить
///    доставку сообщений и обезопасить себя.
///  • Прямую ссылку на сайт rybinsklab.ru.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: MeshTheme.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _appBar(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _hero(),
                    const SizedBox(height: 20),
                    const _Section(
                      icon: Icons.history_edu,
                      title: 'Зачем это приложение',
                      body:
                          'BridgeMesh создан на случай, когда у людей нет '
                          'ни мобильного интернета, ни проводного '
                          'интернета, ни сотовой связи — но есть '
                          'электричество и сами телефоны.\n\n'
                          'Приложение превращает группу устройств в '
                          'одну большую сеть, где каждый телефон — '
                          'одновременно клиент, ретранслятор и узел '
                          'для других. Сообщения идут «цепочкой» через '
                          '10-20 посредников: каждый человек, у которого '
                          'открыто BridgeMesh, помогает донести '
                          'сообщение дальше.',
                    ),
                    const SizedBox(height: 12),
                    const _Section(
                      icon: Icons.engineering,
                      title: 'Разработчик',
                      body:
                          'BridgeMesh создан командой RybinskLab — IT-'
                          'лаборатории из города Рыбинска (Ярославская '
                          'область). Команда занимается кибербезопасностью, '
                          'серверным обслуживанием, мессенджерами '
                          'и IT-консалтингом для бизнеса и частных лиц.\n\n'
                          'Идея приложения родилась из простой мысли: '
                          'в критической ситуации (отключение связи, '
                          'ЧС, отдалённый район, экспедиция) '
                          'люди должны иметь возможность связаться '
                          'друг с другом без инфраструктуры.\n\n'
                          'Сайт: rybinsklab.ru',
                      action: _LinkButton(
                        url: 'https://rybinsklab.ru',
                        label: 'Открыть rybinsklab.ru',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _Section(
                      icon: Icons.bolt,
                      title: 'Как ускорить доставку',
                      body: ''
                          '• Держите приложение открытым — оно работает '
                          'в фоне и ретранслирует пакеты других людей.\n'
                          '• Носите телефон с включённым Bluetooth и Wi-Fi '
                          '— это увеличивает число соседей и стабильность.\n'
                          '• Не отключайте геолокацию — это позволяет '
                          'автоматически находить «комнату» вашего города.\n'
                          '• Расскажите друзьям и знакомым: чем больше '
                          'людей с BridgeMesh, тем выше шанс доставки.\n'
                          '• Заряжайте телефон: ретрансляция потребляет '
                          'энергию, хоть и немного.',
                    ),
                    const SizedBox(height: 12),
                    const _Section(
                      icon: Icons.security,
                      title: 'Безопасность и приватность',
                      body: ''
                          '• Каждое сообщение подписано вашим '
                          '256-битным ключом — никто не сможет '
                          'отправить сообщение от вашего имени.\n'
                          '• ID узла — производный от аппаратного '
                          'fingerprint устройства, его нельзя подделать.\n'
                          '• История имён хранится локально. Можно менять '
                          'имя хоть каждый день.\n'
                          '• Никаких серверов и облаков — всё между '
                          'телефонами в радиусе действия.\n'
                          '• Удаляйте контакты, которые вам больше '
                          'не нужны — данные остаются только у вас.\n'
                          '• Не отправляйте в mesh то, что нельзя '
                          'показывать незнакомцам — увидеть может '
                          'любой узел по пути.',
                    ),
                    const SizedBox(height: 12),
                    const _Section(
                      icon: Icons.share,
                      title: 'Как поделиться приложением',
                      body: ''
                          'Лучший способ распространить BridgeMesh — '
                          'показать его людям лично:\n\n'
                          '• Включите Bluetooth у друга и попросите его '
                          'открыть «Получить приложение» — система '
                          'передаст APK напрямую.\n'
                          '• Покажите QR-код — он содержит ваш '
                          'контактный ID и помогает добавиться.\n'
                          '• Расскажите соседям: один человек с BridgeMesh '
                          'включает всю округу в сеть.\n\n'
                          'Чем больше людей с BridgeMesh, тем выше шанс, '
                          'что сообщения дойдут до адресата.',
                    ),
                    const SizedBox(height: 12),
                    const _Section(
                      icon: Icons.tips_and_updates,
                      title: 'Что делать, если нет связи',
                      body: ''
                          '1. Откройте BridgeMesh. Приложение начнёт '
                          'искать соседей автоматически.\n'
                          '2. Убедитесь, что в верхней панели появилось '
                          '«X узлов» — зелёный индикатор.\n'
                          '3. Напишите в чат — оно само найдёт путь.\n'
                          '4. Если рядом никого нет — носите телефон с '
                          'собой, встречные люди его «подхватят».\n'
                          '5. Смените имя и расскажите друзьям — '
                          'BridgeMesh растёт вместе с сообществом.',
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'BridgeMesh · v1.0 · RybinskLab',
                        style: TextStyle(
                          color: MeshTheme.textSecondary.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appBar(BuildContext context) {
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
            'О приложении',
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

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MeshTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: MeshTheme.headerGradient,
              boxShadow: [
                BoxShadow(
                  color: MeshTheme.primary.withValues(alpha: 0.5),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.hub_rounded,
                size: 48, color: Colors.black),
          ),
          const SizedBox(height: 14),
          const Text(
            'BridgeMesh',
            style: TextStyle(
              color: MeshTheme.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Сеть без интернета — для тех дней, когда связь решает всё',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MeshTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MeshTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: MeshTheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: MeshTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: MeshTheme.textSecondary,
              fontSize: 13,
              height: 1.55,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.url, required this.label});
  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: url));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$url скопирован в буфер обмена')),
            );
          }
        },
        icon: const Icon(Icons.link_rounded, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: MeshTheme.secondary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
