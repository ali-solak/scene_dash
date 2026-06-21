// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'game.dart';

// **************************************************************************
// EcsGenerator
// **************************************************************************

mixin _$PlayerBundle implements SceneDashBundle {
  @override
  void insertInto(World world, Entity entity) {
    final self = this as PlayerBundle;
    world.ensureObjectStore<Position>().insert(entity.index, self.position);
    world.ensureObjectStore<Velocity>().insert(entity.index, self.velocity);
    world
        .ensureObjectStore<Acceleration>()
        .insert(entity.index, self.acceleration);
    world.ensureTagStore<Player>().add(entity.index);
  }
}

class _$SpawnPlayerSystemAdapter
    implements SystemAdapter, SystemAccessProvider {
  _$SpawnPlayerSystemAdapter(this._system);

  final SpawnPlayerSystem _system;
  late final Commands _p0;
  late final EventWriter<PlayerSpawned> _p1;

  @override
  void initialize(World world) {
    _p0 = world.commands;
    world.registerEvent<PlayerSpawned>();
    _p1 = world.eventChannel<PlayerSpawned>().writer();
  }

  @override
  SystemAccess get access => const SystemAccess(
        reads: <Type>{},
        writes: <Type>{},
      );

  @override
  void run() {
    _system.run(_p0, _p1);
  }
}

base mixin _$SpawnPlayerSystem on GameSystem {
  @override
  SystemAdapter createAdapter() =>
      _$SpawnPlayerSystemAdapter(this as SpawnPlayerSystem);
}

class _$MovePlayerSystemAdapter implements SystemAdapter, SystemAccessProvider {
  _$MovePlayerSystemAdapter(this._system);

  final MovePlayerSystem _system;
  late final Query2<Position, Velocity> _p0;
  late final FixedTime _p1;

  @override
  void initialize(World world) {
    world.ensureObjectStore<Position>();
    world.ensureObjectStore<Velocity>();
    world.ensureTagStore<Player>();
    _p0 = world.query2<Position, Velocity>(
        withTypes: const <Type>[Player], withoutTypes: const <Type>[]);
    _p1 = world.resources.get<FixedTime>();
  }

  @override
  SystemAccess get access => const SystemAccess(
        reads: <Type>{Velocity},
        writes: <Type>{Position},
      );

  @override
  void run() {
    _system.run(_p0, _p1);
  }
}

base mixin _$MovePlayerSystem on GameSystem {
  @override
  SystemAdapter createAdapter() =>
      _$MovePlayerSystemAdapter(this as MovePlayerSystem);
}

class _$CountSpawnsSystemAdapter
    implements SystemAdapter, SystemAccessProvider {
  _$CountSpawnsSystemAdapter(this._system);

  final CountSpawnsSystem _system;
  late final EventReader<PlayerSpawned> _p0;
  late final SpawnLog _p1;

  @override
  void initialize(World world) {
    world.registerEvent<PlayerSpawned>();
    _p0 = world.eventChannel<PlayerSpawned>().reader();
    _p1 = world.resources.get<SpawnLog>();
  }

  @override
  SystemAccess get access => const SystemAccess(
        reads: <Type>{},
        writes: <Type>{},
      );

  @override
  void run() {
    _system.run(_p0, _p1);
  }
}

base mixin _$CountSpawnsSystem on GameSystem {
  @override
  SystemAdapter createAdapter() =>
      _$CountSpawnsSystemAdapter(this as CountSpawnsSystem);
}

class _$TrackMotionSystemAdapter
    implements SystemAdapter, SystemAccessProvider {
  _$TrackMotionSystemAdapter(this._system);

  final TrackMotionSystem _system;
  late final Query3<Position, Velocity, Acceleration> _p0;
  late final MotionLog _p1;

  @override
  void initialize(World world) {
    world.ensureObjectStore<Position>();
    world.ensureObjectStore<Velocity>();
    world.ensureObjectStore<Acceleration>();
    _p0 = world.query3<Position, Velocity, Acceleration>(
        withTypes: const <Type>[], withoutTypes: const <Type>[]);
    _p1 = world.resources.get<MotionLog>();
  }

  @override
  SystemAccess get access => const SystemAccess(
        reads: <Type>{Position, Velocity, Acceleration},
        writes: <Type>{},
      );

  @override
  void run() {
    _system.run(_p0, _p1);
  }
}

base mixin _$TrackMotionSystem on GameSystem {
  @override
  SystemAdapter createAdapter() =>
      _$TrackMotionSystemAdapter(this as TrackMotionSystem);
}

base mixin _$PlayerPlugin on Plugin {
  @override
  List<Type> get dependencies => const <Type>[InputPlugin];
}
