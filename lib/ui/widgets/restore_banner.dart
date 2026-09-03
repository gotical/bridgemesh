import 'package:flutter/material.dart';

import '../../theme/mesh_theme.dart';

/// Баннер, который показывается, если данные узла были
/// восстановлены из бэкапа, созданного на другом устройстве.
class RestoredBanner extends StatelessWidget {
  const RestoredBanner({
    super.key,
    required this.originAlias,
    required this.originNodeId,
    required this.onDismiss,
  });

  final String originAlias;
  final String originNodeId;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: MeshTheme.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MeshTheme.accent.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.swap_horiz,
            color: MeshTheme.accent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Восстановлено из бэкапа',
                  style: TextStyle(
                    color: MeshTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Данные с узла «$originAlias». '
                  'Сейчас это другое устройство — nodeId будет новый.',
                  style: const TextStyle(
                    color: MeshTheme.textSecondary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
            color: MeshTheme.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          ),
        ],
      ),
    );
  }
}
