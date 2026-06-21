import 'package:headless_example/game.dart';
import 'package:scene_dash/scene_dash.dart';
import 'package:test/test.dart';

void main() {
  test('generated adapters drive spawn, move and event counting', () {
    // No manual store registration and no hand-written adapters: everything is
    // wired by the code the generator produced for game.dart.
    final app = App()
      ..addPlugin(const InputPlugin())
      ..addPlugin(const PlayerPlugin());
    app.start();

    // Startup spawned exactly one player at the origin (bundle insert applied
    // after the startup schedule).
    final atStart = <Position>[];
    app.world.query1<Position>().each((_, p) => atStart.add(p));
    expect(atStart, hasLength(1));
    expect(atStart.single.x, 0);
    expect(atStart.single.y, 0);

    // A fixed step integrates motion: dt = 0.5, velocity = (1, 2).
    app.runSchedule(Schedules.fixedPrePhysics);
    final moved = <Position>[];
    app.world.query1<Position>().each((_, p) => moved.add(p));
    expect(moved.single.x, closeTo(0.5, 1e-9));
    expect(moved.single.y, closeTo(1.0, 1e-9));

    // The update schedule consumes the single PlayerSpawned event and the
    // read-only Query3 system samples the one mover.
    app.runSchedule(Schedules.update);
    expect(app.world.resources.get<SpawnLog>().count, 1);
    expect(app.world.resources.get<MotionLog>().sampled, 1);

    // The generated access metadata is honoured: the writing system (Position)
    // and the read-only Query3 system are in different schedules / non-conflicting,
    // so no access conflicts are reported.
    expect(app.accessConflicts, isEmpty);

    // A second fixed step keeps integrating.
    app.runSchedule(Schedules.fixedPrePhysics);
    final moved2 = <Position>[];
    app.world.query1<Position>().each((_, p) => moved2.add(p));
    expect(moved2.single.x, closeTo(1.0, 1e-9));
  });

  test('generated @GamePlugin(requires:) is enforced as a dependency', () {
    // PlayerPlugin's generated _$PlayerPlugin mixin declares InputPlugin as a
    // dependency; adding it without InputPlugin must fail.
    expect(() => App()..addPlugin(const PlayerPlugin()), throwsStateError);
  });
}
