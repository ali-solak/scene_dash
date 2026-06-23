// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rocks.dart';

// **************************************************************************
// EcsGenerator
// **************************************************************************

class $SpawnRocksSystemAdapter implements SystemAdapter, SystemAccessProvider {
  $SpawnRocksSystemAdapter(this._system);

  final SpawnRocksSystem _system;
  late final Commands _p0;
  late final RockSpawner _p1;
  late final GameState _p2;
  late final FixedTime _p3;

  @override
  void initialize(World world) {
    _p0 = world.commands;
    _p1 = world.resources.get<RockSpawner>();
    _p2 = world.resources.get<GameState>();
    _p3 = world.resources.get<FixedTime>();
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{}, writes: <Type>{});

  @override
  void run() {
    _system.run(_p0, _p1, _p2, _p3);
  }
}

/// Schedulable descriptor for [SpawnRocksSystem]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final spawnRocksSystem = SystemDescriptor(
  const SystemRef('package:scene_game/rocks/rocks.dart', 'SpawnRocksSystem'),
  () => $SpawnRocksSystemAdapter(const SpawnRocksSystem()),
);

class $CleanupRocksSystemAdapter
    implements SystemAdapter, SystemAccessProvider {
  $CleanupRocksSystemAdapter(this._system);

  final CleanupRocksSystem _system;
  late final Query1<SceneNodeRef> _p0;
  late final Commands _p1;

  @override
  void initialize(World world) {
    world.ensureObjectStore<SceneNodeRef>();
    world.ensureTagStore<Rock>();
    _p0 = world.query1<SceneNodeRef>(
      withTypes: const <Type>[Rock],
      withoutTypes: const <Type>[],
    );
    _p1 = world.commands;
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{SceneNodeRef}, writes: <Type>{});

  @override
  void run() {
    _system.run(_p0, _p1);
  }
}

/// Schedulable descriptor for [CleanupRocksSystem]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final cleanupRocksSystem = SystemDescriptor(
  const SystemRef('package:scene_game/rocks/rocks.dart', 'CleanupRocksSystem'),
  () => $CleanupRocksSystemAdapter(const CleanupRocksSystem()),
);

class $SpawnRockTrailsAdapter implements SystemAdapter, SystemAccessProvider {
  late final Scene _p0;
  late final RockTrails _p1;

  @override
  void initialize(World world) {
    _p0 = world.resources.get<Scene>();
    _p1 = world.resources.get<RockTrails>();
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{}, writes: <Type>{});

  @override
  void run() {
    spawnRockTrails(_p0, _p1);
  }
}

/// Schedulable descriptor for [spawnRockTrails]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final spawnRockTrailsSystem = SystemDescriptor(
  const SystemRef('package:scene_game/rocks/rocks.dart', 'spawnRockTrails'),
  () => $SpawnRockTrailsAdapter(),
);

class $UpdateRockTrailsAdapter implements SystemAdapter, SystemAccessProvider {
  late final Query1<SceneNodeRef> _p0;
  late final RockTrails _p1;

  @override
  void initialize(World world) {
    world.ensureObjectStore<SceneNodeRef>();
    world.ensureTagStore<Rock>();
    world.ensureTagStore<Flaming>();
    _p0 = world.query1<SceneNodeRef>(
      withTypes: const <Type>[Rock, Flaming],
      withoutTypes: const <Type>[],
    );
    _p1 = world.resources.get<RockTrails>();
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{SceneNodeRef}, writes: <Type>{});

  @override
  void run() {
    updateRockTrails(_p0, _p1);
  }
}

/// Schedulable descriptor for [updateRockTrails]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final updateRockTrailsSystem = SystemDescriptor(
  const SystemRef('package:scene_game/rocks/rocks.dart', 'updateRockTrails'),
  () => $UpdateRockTrailsAdapter(),
);

mixin _$RockBundle implements SceneDashBundle {
  @override
  void insertInto(World world, Entity entity) {
    final self = this as RockBundle;
    world.ensureTagStore<Rock>().add(entity.index);
    world.ensureObjectStore<SceneNodeRef>().insert(entity.index, self.node);
    world.ensureTagStore<PhysicsDriven>().add(entity.index);
  }
}
