import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Экран сканирования QR-кода с камеры.
///
/// При успешном считывании возвращает строку из QR — обычно
/// это `bridgemesh://contact?id=...&alias=...&group=...&v=1`.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  /// Запустить сканирование и вернуть строку из QR.
  /// Возвращает null, если пользователь отменил.
  static Future<String?> scan(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
  }

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final MobileScannerController _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
    facing: CameraFacing.back,
  );
  bool _handled = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_handled) return;
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v == null || v.isEmpty) continue;
      _handled = true;
      _ctrl.stop();
      Navigator.of(context).pop(v);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _ctrl,
            onDetect: _onDetect,
            errorBuilder: (ctx, err, child) => _ErrorView(
              message: _errorMessage(err),
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          // Overlay с рамкой
          IgnorePointer(
            child: CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _ScannerOverlayPainter(),
            ),
          ),
          // Top bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Material(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const Spacer(),
                    Material(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.flash_on, color: Colors.white),
                        tooltip: 'Фонарик',
                        onPressed: () => _ctrl.toggleTorch(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom hint
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Наведите камеру на QR-код',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Контакт добавится автоматически',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _errorMessage(MobileScannerException err) {
    switch (err.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Нет разрешения на камеру.\nОткройте настройки и разрешите '
            'BridgeMesh использовать камеру.';
      case MobileScannerErrorCode.unsupported:
        return 'Камера не поддерживается на этом устройстве.';
      case MobileScannerErrorCode.controllerUninitialized:
        return 'Камера ещё не готова.';
      default:
        return 'Не удалось запустить камеру.\n${err.errorDetails?.message ?? ''}';
    }
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cutSize = size.width * 0.7;
    final left = (size.width - cutSize) / 2;
    final top = (size.height - cutSize) / 2;
    final rect = Rect.fromLTWH(left, top, cutSize, cutSize);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(20));

    // Затемнение вокруг рамки
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final inner = Path()..addRRect(rrect);
    final overlayPath = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(overlayPath, overlayPaint);

    // Углы рамки (декоративные)
    final cornerLen = 28.0;
    final cornerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // top-left
    canvas.drawLine(rect.topLeft.translate(0, cornerLen),
        rect.topLeft, cornerPaint);
    canvas.drawLine(rect.topLeft,
        rect.topLeft.translate(cornerLen, 0), cornerPaint);
    // top-right
    canvas.drawLine(rect.topRight.translate(-cornerLen, 0),
        rect.topRight, cornerPaint);
    canvas.drawLine(rect.topRight,
        rect.topRight.translate(0, cornerLen), cornerPaint);
    // bottom-left
    canvas.drawLine(rect.bottomLeft.translate(0, -cornerLen),
        rect.bottomLeft, cornerPaint);
    canvas.drawLine(rect.bottomLeft,
        rect.bottomLeft.translate(cornerLen, 0), cornerPaint);
    // bottom-right
    canvas.drawLine(rect.bottomRight.translate(-cornerLen, 0),
        rect.bottomRight, cornerPaint);
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight.translate(0, -cornerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onBack});
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography,
                    size: 64, color: Colors.white54),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: onBack,
                  child: const Text('Назад'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
