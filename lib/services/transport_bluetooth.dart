import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'power_mode.dart';
import 'transport.dart';

/// Bluetooth-транспорт.
///
/// Каждое устройство одновременно:
///   • Advertise-ит сервис «BridgeMesh» (имя = Mesh alias)
///   • Сканирует округу на этот сервис
///   • Подключается к обнаруженным узлам и обменивается пакетами
///     через writeCharacteristic / notifyCharacteristic
///
/// В режиме энергосбережения скан и подключения приостановлены;
/// узел продолжает принимать notify от уже подключённых соседей
/// и ретранслировать сообщения, когда экран/процесс позволяет.
class BluetoothTransport implements MeshTransport {
  @override
  String get name => 'bluetooth';

  @override
  bool get isRunning => _running;

  bool _running = false;
  PowerMode _mode = PowerMode.normal;
  PowerTimings _timings = PowerTimings.of(PowerMode.normal);
  Timer? _scanTimer;

  static const String serviceUuid =
      '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String txUuid =
      '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // write
  static const String rxUuid =
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // notify

  final _neighborsCtrl = StreamController<NeighborEvent>.broadcast();
  final FragmentAssembler _assembler = FragmentAssembler();

  @override
  Stream<Telegram> get incoming => _assembler.output;
  @override
  Stream<NeighborEvent> get neighbors => _neighborsCtrl.stream;

  StreamSubscription? _scanSub;
  final Map<String, BluetoothDevice> _devices = {};
  final Map<String, BluetoothCharacteristic> _rxChars = {};
  final Map<String, BluetoothCharacteristic> _txChars = {};

  /// Применить режим энергопотребления.
  void applyPowerMode(PowerMode mode) {
    final wasRunning = _running;
    if (mode == _mode) return;
    final prev = _mode;
    _mode = mode;
    _timings = PowerTimings.of(mode);

    if (mode == PowerMode.economy) {
      // Останавливаем сканирование и отключаемся — экономим заряд.
      // Ретрансляция уже подключённых пакетов остаётся через notify.
      _scanSub?.cancel();
      _scanSub = null;
      _scanTimer?.cancel();
      try {
        FlutterBluePlus.stopScan();
      } catch (_) {}
      // Отключаемся от тех, к кому подключились — экономим радио.
      for (final d in _devices.values) {
        try {
          d.disconnect();
        } catch (_) {}
      }
      _devices.clear();
      _rxChars.clear();
      _txChars.clear();
    } else if (wasRunning && prev == PowerMode.economy) {
      // Выходим из эконома — возобновляем сканирование.
      _scheduleScan();
    }
  }

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      _scheduleScan();
      _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);
    } catch (_) {
      // Разрешения не выданы — транспорт молча отключается.
      _running = false;
    }
  }

  void _scheduleScan() {
    _scanTimer?.cancel();
    if (_mode == PowerMode.economy) return;
    // Цикл: window секунд сканируем, потом ждём до gap.
    _scanTimer = Timer.periodic(_timings.bleScanGap, (_) async {
      if (!_running || _mode == PowerMode.economy) return;
      try {
        await FlutterBluePlus.startScan(
          timeout: _timings.bleScanWindow,
          withServices: [Guid(serviceUuid)],
        );
      } catch (_) {}
    });
    // Запустим первый цикл сразу.
    try {
      FlutterBluePlus.startScan(
        timeout: _timings.bleScanWindow,
        withServices: [Guid(serviceUuid)],
      );
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    _running = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    for (final d in _devices.values) {
      try {
        await d.disconnect();
      } catch (_) {}
    }
    _devices.clear();
    _rxChars.clear();
    _txChars.clear();
  }

  void _onScanResults(List<ScanResult> results) {
    if (_mode == PowerMode.economy) return;
    for (final r in results) {
      if (r.advertisementData.serviceUuids
          .any((g) => g.toString().toLowerCase().contains(serviceUuid))) {
        final id = _deviceId(r.device);
        _neighborsCtrl.add(
          NeighborEvent(
            id: id,
            name: r.advertisementData.advName.isNotEmpty
                ? r.advertisementData.advName
                : r.device.platformName,
            rssi: r.rssi,
            gone: false,
            addr: r.device.remoteId.str,
          ),
        );
        if (!_devices.containsKey(id)) {
          _devices[id] = r.device;
          _connect(id, r.device);
        }
      }
    }
  }

  String _deviceId(BluetoothDevice d) =>
      d.remoteId.str.hashCode.toRadixString(16).padLeft(8, '0');

  Future<void> _connect(String id, BluetoothDevice device) async {
    if (_mode == PowerMode.economy) return;
    try {
      await device.connect(timeout: const Duration(seconds: 8));
      final services = await device.discoverServices();
      for (final s in services) {
        if (s.uuid.toString().toLowerCase().contains(serviceUuid)) {
          for (final c in s.characteristics) {
            if (c.uuid.toString().toLowerCase().contains(txUuid)) {
              _txChars[id] = c;
            }
            if (c.uuid.toString().toLowerCase().contains(rxUuid)) {
              _rxChars[id] = c;
              await c.setNotifyValue(true);
              c.lastValueStream.listen((data) {
                _assembler.ingest(
                  Uint8List.fromList(data),
                  id,
                  -50,
                  name,
                );
              });
            }
          }
        }
      }
    } catch (_) {
      // Не удалось подключиться — узел просто пропустим.
    }
  }

  @override
  Future<void> broadcast(Uint8List data) async {
    if (_mode == PowerMode.economy) return;
    for (final entry in _txChars.entries) {
      try {
        for (var i = 0; i < data.length; i += 180) {
          final chunk = data.sublist(
            i,
            i + 180 > data.length ? data.length : i + 180,
          );
          await entry.value.write(
            chunk,
            withoutResponse: true,
            timeout: 5,
          );
        }
      } catch (_) {}
    }
  }

  @override
  Future<void> sendTo(String remoteId, Uint8List data) async {
    if (_mode == PowerMode.economy) return;
    final c = _txChars[remoteId];
    if (c == null) return;
    try {
      for (var i = 0; i < data.length; i += 180) {
        final chunk = data.sublist(
          i,
          i + 180 > data.length ? data.length : i + 180,
        );
        await c.write(chunk, withoutResponse: true, timeout: 5);
      }
    } catch (_) {}
  }
}
