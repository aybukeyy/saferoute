// Smoke test for the freshly-extracted assets/road_graph.bin produced by
// tools/extract_osm.py. Bypasses the Flutter asset bundle and reads the file
// straight off disk so the test runs under `flutter test` without a binding.

import 'dart:io';
import 'dart:typed_data';

import 'package:app/routing/osm_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseBytes loads the bundled road_graph.bin', () {
    final File file = File('assets/road_graph.bin');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Run `python tools/extract_osm.py ...` first.',
    );

    final Uint8List bytes = file.readAsBytesSync();
    final ByteData data = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );

    final OsmGraph graph = OsmGraph.parseBytes(data);

    expect(graph.nodes.length, greaterThan(1000));
    expect(graph.edges.length, greaterThan(1000));
    expect(graph.geohashIndex, isNotEmpty);

    // Spot-check coordinates fall inside the Beşiktaş bbox (with a tiny margin).
    for (final n in graph.nodes.take(50)) {
      expect(n.latitude, inInclusiveRange(41.039, 41.081));
      expect(n.longitude, inInclusiveRange(28.984, 29.046));
    }

    // Edges reference valid node ids.
    for (final e in graph.edges.take(50)) {
      expect(e.u, inInclusiveRange(0, graph.nodes.length - 1));
      expect(e.v, inInclusiveRange(0, graph.nodes.length - 1));
      expect(e.lengthMeters, greaterThan(0));
    }
  });
}
