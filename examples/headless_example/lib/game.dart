import 'package:scene_dash/scene_dash.dart';

part 'game.g.dart';

// --- Components ---

@ObjectComponent()
final class Position {
  double x;
  double y;
  Position(this.x, this.y);
}

@ObjectComponent()
final class Velocity {
  final double x;
  final double y;
  const Velocity(this.x, this.y);
}

@ObjectComponent()
final class Acceleration {
  double x;
  double y;
  Acceleration(this.x, this.y);
}

@Tag()
final class Player {
  const Player();
}

// --- Event & resource ---

final class PlayerSpawned {
  final Entity entity;
  const PlayerSpawned(this.entity);
}

final class SpawnLog {
  int count = 0;
}

final class InputState {
  double horizontal = 0;
}

final class MotionLog {
  int sampled = 0;
}

// --- Bundle ---

@Bundle()
final class PlayerBundle with _$PlayerBundle {
  final Position position;
  final Velocity velocity;
  final Acceleration acceleration;
  final Player player;

  PlayerBundle({required this.position, required this.velocity})
      : acceleration = Acceleration(0, 0),
        player = const Player();
}

// --- Systems ---

@System()
final class SpawnPlayerSystem extends GameSystem with _$SpawnPlayerSystem {
  const SpawnPlayerSystem();

  void run(Commands commands, EventWriter<PlayerSpawned> spawned) {
    final entity = commands.spawn(
      PlayerBundle(position: Position(0, 0), velocity: const Velocity(1, 2)),
    );
    spawned.send(PlayerSpawned(entity));
  }
}

@System()
final class MovePlayerSystem extends GameSystem with _$MovePlayerSystem {
  const MovePlayerSystem();

  void run(
    @Query(writes: [Position], requires: [Player])
    Query2<Position, Velocity> players,
    @Resource() FixedTime time,
  ) {
    players.each((entity, position, velocity) {
      position
        ..x += velocity.x * time.delta
        ..y += velocity.y * time.delta;
    });
  }
}

@System()
final class CountSpawnsSystem extends GameSystem with _$CountSpawnsSystem {
  const CountSpawnsSystem();

  void run(EventReader<PlayerSpawned> spawned, @Resource() SpawnLog log) {
    log.count += spawned.drain().length;
  }
}

/// A read-only `Query3` system: it samples every mover. All three components are
/// reads (no `writes`), so it never conflicts with the writing systems.
@System()
final class TrackMotionSystem extends GameSystem with _$TrackMotionSystem {
  const TrackMotionSystem();

  void run(
    @Query() Query3<Position, Velocity, Acceleration> movers,
    @Resource() MotionLog log,
  ) {
    movers.each((entity, position, velocity, acceleration) {
      log.sampled++;
    });
  }
}

// --- Plugins ---

@GamePlugin()
final class InputPlugin extends Plugin {
  const InputPlugin();

  @override
  void build(AppBuilder app) {
    app.insertResource<InputState>(InputState());
  }
}

@GamePlugin(requires: [InputPlugin])
final class PlayerPlugin extends Plugin with _$PlayerPlugin {
  const PlayerPlugin();

  @override
  void build(AppBuilder app) {
    app
      ..addEvent<PlayerSpawned>()
      ..insertResource<FixedTime>(FixedTime()..delta = 0.5)
      ..insertResource<SpawnLog>(SpawnLog())
      ..insertResource<MotionLog>(MotionLog())
      ..addSystem(
        const SpawnPlayerSystem(),
        schedule: Schedules.startup,
        label: const SystemLabel('player.spawn'),
      )
      ..addSystem(
        const MovePlayerSystem(),
        schedule: Schedules.fixedPrePhysics,
        label: const SystemLabel('player.move'),
      )
      ..addSystem(
        const CountSpawnsSystem(),
        schedule: Schedules.update,
        label: const SystemLabel('player.countSpawns'),
      )
      ..addSystem(
        const TrackMotionSystem(),
        schedule: Schedules.update,
        label: const SystemLabel('player.trackMotion'),
      );
  }
}
