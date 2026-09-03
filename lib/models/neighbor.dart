/// Запись о соседнем узле.
class Neighbor {
  final String id;
  final String transport;     // 'bluetooth' / 'wifi' / 'nearby'
  String name;
  int rssi;                   // уровень сигнала (для BLE)
  int lastSeen;               // millisSinceEpoch
  bool isRelay;               // готов ли ретранслировать чужие пакеты
  int hopsAway;               // дистанция в hop'ах до узла
  String? addr;               // MAC/BSSID/идентификатор сессии

  Neighbor({
    required this.id,
    required this.transport,
    required this.name,
    required this.rssi,
    required this.lastSeen,
    this.isRelay = true,
    this.hopsAway = 1,
    this.addr,
  });

  bool get isStale {
    final age = DateTime.now().millisecondsSinceEpoch - lastSeen;
    return age > 60_000; // 60 секунд
  }

  Neighbor copyWith({
    String? name,
    int? rssi,
    int? lastSeen,
    bool? isRelay,
    int? hopsAway,
    String? addr,
  }) {
    return Neighbor(
      id: id,
      transport: transport,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
      isRelay: isRelay ?? this.isRelay,
      hopsAway: hopsAway ?? this.hopsAway,
      addr: addr ?? this.addr,
    );
  }
}
