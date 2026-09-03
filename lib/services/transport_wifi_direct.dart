import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'transport.dart';
import 'power_mode.dart';

/// Wi-Fi Direct / LAN транспорт.
///
/// В чистом виде Wi-Fi Direct API недоступен из Flutter, поэтому
/// транспорт использует два канала, которые работают через локальные
/// сети без интернета:
///
///  • UDP broadcast на 255.255.255.255:47474 — обнаружение и обмен
///    внутри одной Wi-Fi сети (или Wi-Fi Direct группы).
///
/// Роутер НЕ обязателен: можно соединить два устройства через
/// Wi-Fi Direct (точка-точка) или через мобильную точку доступа.
/// В этом режиме устройства договариваются через Android-настройку
/// «Wi-Fi Direct», а дальше используется тот же канал 47474.
///  • Hotspot TCP-сервер на порту 47475 — установление прямого
///    соединения между двумя устройствами.
///
/// Это даёт радиус 50-200 м на улице и неограниченную пропускную
/// способность по сравнению с BLE (≈10 КБ/с).
class WifiDirectTransport implements MeshTransport {
  @override
  String get name => 'wifi';

  @override
  bool get isRunning => _running;

  bool _running = false;
  final int _udpPort = 47474;
  final int _tcpPort = 47475;

  RawDatagramSocket? _udp;
  ServerSocket? _tcpServer;
  final Map<String, Socket> _tcpPeers = {};
  final _incomingCtrl = StreamController<Telegram>.broadcast();
  final _neighborsCtrl = StreamController<NeighborEvent>.broadcast();
  final FragmentAssembler _assembler = FragmentAssembler();

  @override
  Stream<Telegram> get incoming => _assembler.output;
  @override
  Stream<NeighborEvent> get neighbors => _neighborsCtrl.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      _udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _udpPort,
        reuseAddress: true,
      );
      _udp!.broadcastEnabled = true;
      _udp!.listen((event) {
        if (event == RawSocketEvent.read) {
          while (true) {
            final dg = _udp!.receive();
            if (dg == null) break;
            _onUdp(dg);
          }
        }
      });
      _tcpServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _tcpPort,
        shared: true,
      );
      _tcpServer!.listen(_onTcpConnect);
      _startBeacon();
    } catch (e) {
      _running = false;
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    _beaconTimer?.cancel();
    try {
      _udp?.close();
    } catch (_) {}
    try {
      _tcpServer?.close();
    } catch (_) {}
    for (final s in _tcpPeers.values) {
      try {
        await s.close();
      } catch (_) {}
    }
    _tcpPeers.clear();
    await _incomingCtrl.close();
    await _neighborsCtrl.close();
  }

  Timer? _beaconTimer;
  PowerMode _mode = PowerMode.normal;
  PowerTimings _timings = PowerTimings.of(PowerMode.normal);

  /// Применить режим энергопотребления. В эконом-режиме Wi-Fi
  /// только слушает, но не вещает — экономим радио и заряд.
  void applyPowerMode(PowerMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    _timings = PowerTimings.of(mode);
    if (_running) {
      _startBeacon();
    }
  }

  void _startBeacon() {
    _beaconTimer?.cancel();
    final gap = _mode == PowerMode.economy
        ? _timings.wifiHelloGap
        : const Duration(seconds: 3);
    _beaconTimer = Timer.periodic(gap, (_) {
      if (!_running) return;
      final pkt = utf8.encode('BM-BEACON');
      try {
        _udp?.send(pkt, InternetAddress('255.255.255.255'), _udpPort);
      } catch (_) {}
    });
  }

  void _onUdp(Datagram event) {
    final data = event.data;
    if (data.isEmpty) return;
    final text = utf8.decode(data, allowMalformed: true);
    if (text.startsWith('BM-HELLO|')) {
      // HELLO|<nodeId>|<alias>
      final parts = text.split('|');
      if (parts.length >= 3) {
        final id = parts[1];
        final alias = parts[2];
        final addr = event.address.address;
        _neighborsCtrl.add(
          NeighborEvent(
            id: id,
            name: alias,
            rssi: -40,
            gone: false,
            addr: addr,
          ),
        );
        // Ответим, чтобы сосед нас увидел (даже если он не успеет нас
        // услышать через broadcast).
        final reply = utf8.encode('BM-REPLY|$id');
        try {
          _udp?.send(reply, event.address, _udpPort);
        } catch (_) {}
      }
      return;
    }
    if (text.startsWith('BM-REPLY|')) {
      // Ничего особенного не делаем, событие соседа уже пришло.
      return;
    }
    // Произвольный пакет.
    _assembler.ingest(
      Uint8List.fromList(data),
      event.address.address,
      -40,
      name,
    );
  }

  void _onTcpConnect(Socket socket) {
    final addr = socket.remoteAddress.address;
    socket.listen(
      (data) {
        _assembler.ingest(
          Uint8List.fromList(data),
          addr,
          -30,
          name,
        );
      },
      onError: (_) {},
      onDone: () {
        _tcpPeers.remove(addr);
      },
      cancelOnError: false,
    );
    _tcpPeers[addr] = socket;
  }

  @override
  Future<void> broadcast(Uint8List data) async {
    try {
      _udp?.send(data, InternetAddress('255.255.255.255'), _udpPort);
    } catch (_) {}
    for (final s in _tcpPeers.values.toList()) {
      try {
        s.add(data);
      } catch (_) {}
    }
  }

  @override
  Future<void> sendTo(String remoteId, Uint8List data) async {
    if (_tcpPeers.containsKey(remoteId)) {
      try {
        _tcpPeers[remoteId]!.add(data);
      } catch (_) {}
      return;
    }
    // Пробуем подключиться к этому адресу по TCP.
    try {
      final sock = await Socket.connect(remoteId, _tcpPort)
          .timeout(const Duration(seconds: 3));
      sock.add(data);
      _tcpPeers[remoteId] = sock;
    } catch (_) {}
  }
}
