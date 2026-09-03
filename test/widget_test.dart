import 'package:flutter_test/flutter_test.dart';

import 'package:bridgemesh/models/mesh_packet.dart';

void main() {
  test('MeshPacket кодируется и декодируется без потерь', () {
    final pkt = MeshPacket(
      type: MeshMessageType.text,
      from: 'Узел-1234',
      to: 'Узел-5678',
      id: 'abc',
      ttl: 5,
      hop: 2,
      signature: 'sig',
      payload: {'text': 'Привет, mesh!'},
    );
    final bytes = pkt.encode();
    final restored = MeshPacket.decode(bytes)!;
    expect(restored.type, MeshMessageType.text);
    expect(restored.from, 'Узел-1234');
    expect(restored.to, 'Узел-5678');
    expect(restored.payload['text'], 'Привет, mesh!');
    expect(restored.ttl, 5);
  });
}
