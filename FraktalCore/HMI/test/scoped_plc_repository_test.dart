import 'package:flutter_test/flutter_test.dart';
import 'package:fraktal_hmi/data/scoped_plc_repository.dart';
import 'package:fraktal_hmi/data/sim_repository.dart';
import 'package:fraktal_hmi/domain/fieldbus.dart';

void main() {
  test('configured root scope filters reads and rejects writes outside it',
      () async {
    final scoped = ScopedPlcRepository(
      SimRepository(),
      allowedRoots: const ['StationA'],
      configured: true,
    );
    addTearDown(scoped.dispose);

    final roots = await scoped.forest().firstWhere((items) => items.isNotEmpty);
    expect(roots.map((root) => root.path), ['StationA']);

    final bus = await scoped.fieldbus().firstWhere((items) => items.isNotEmpty);
    final channelPaths = <String>[];
    void walk(List<BusNode> nodes) {
      for (final node in nodes) {
        channelPaths.addAll(node.channels.map((channel) => channel.path));
        walk(node.children);
      }
    }

    walk(bus);
    expect(channelPaths, isNotEmpty);
    expect(channelPaths.every((path) => path.startsWith('StationA.')), isTrue);
    expect(await scoped.start('ConveyorB'), isFalse);
    expect((await scoped.releaseReportStart('ConveyorB')).released, isFalse);
    expect(await scoped.login('ConveyorB', 'admin1', '2468'), isFalse);
  });
}
