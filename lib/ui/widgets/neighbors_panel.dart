import 'package:flutter/material.dart';

import '../../services/routing_service.dart';
import '../../theme/mesh_theme.dart';

class NeighborsPanel extends StatefulWidget {
  const NeighborsPanel({super.key, required this.routing});
  final RoutingService routing;

  @override
  State<NeighborsPanel> createState() => _NeighborsPanelState();
}

class _NeighborsPanelState extends State<NeighborsPanel> {
  @override
  void initState() {
    super.initState();
    widget.routing.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.routing.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final ns = widget.routing.neighbors;
    return ns.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: MeshTheme.primary.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.satellite_alt_outlined,
                      size: 56,
                      color: MeshTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Ищу соседей...',
                    style: TextStyle(
                      color: MeshTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'BridgeMesh сканирует Bluetooth и Wi-Fi Direct.\n'
                    'Попросите друзей открыть приложение рядом.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MeshTheme.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ns.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final n = ns[i];
              final rssi = n.rssi;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MeshTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: MeshTheme.primary.withValues(alpha: 0.12),
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: MeshTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.name.isEmpty ? n.id : n.name,
                            style: const TextStyle(
                              color: MeshTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${n.transport} • ${n.addr ?? ''}',
                            style: const TextStyle(
                              color: MeshTheme.textSecondary,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    _SignalBars(rssi: rssi),
                    const SizedBox(width: 8),
                    Text(
                      '$rssi dBm',
                      style: const TextStyle(
                        color: MeshTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.rssi});
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final bars = rssi >= -60
        ? 4
        : rssi >= -70
            ? 3
            : rssi >= -80
                ? 2
                : 1;
    return Row(
      children: List.generate(4, (i) {
        final filled = i < bars;
        return Container(
          width: 3,
          height: 4 + i * 3.0,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: filled
                ? MeshTheme.primary
                : MeshTheme.textSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
