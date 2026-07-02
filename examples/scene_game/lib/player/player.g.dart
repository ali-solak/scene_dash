// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player.dart';

// **************************************************************************
// EcsGenerator
// **************************************************************************

class $SpawnPlayerAdapter implements SystemAdapter, SystemAccessProvider {
  late final Commands _p0;

  @override
  void initialize(World world) {
    _p0 = world.commands;
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{}, writes: <Type>{});

  @override
  void run() {
    spawnPlayer(_p0);
  }
}

/// Schedulable descriptor for [spawnPlayer]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final spawnPlayerSystem = SystemDescriptor(
  const SystemRef('package:scene_game/player/player.dart', 'spawnPlayer'),
  () => $SpawnPlayerAdapter(),
);

class $MovePlayerAdapter implements SystemAdapter, SystemAccessProvider {
  late final Single<SceneNodeRef> _p0;
  late final InputState _p1;
  late final FixedTime _p2;
  late final PlayerKnockback _p3;

  @override
  void initialize(World world) {
    world.ensureObjectStore<SceneNodeRef>();
    world.ensureTagStore<Player>();
    _p0 = Single<SceneNodeRef>(
      world.query1<SceneNodeRef>(
        withTypes: const <Type>[Player],
        withoutTypes: const <Type>[],
      ),
    );
    _p1 = world.resources.get<InputState>();
    _p2 = world.resources.get<FixedTime>();
    _p3 = world.resources.get<PlayerKnockback>();
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{}, writes: <Type>{SceneNodeRef});

  @override
  void run() {
    movePlayer(_p0, _p1, _p2, _p3);
  }
}

/// Schedulable descriptor for [movePlayer]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final movePlayerSystem = SystemDescriptor(
  const SystemRef('package:scene_game/player/player.dart', 'movePlayer'),
  () => $MovePlayerAdapter(),
);

class $AnimateCrabLegsAdapter implements SystemAdapter, SystemAccessProvider {
  late final Single<PlayerVisuals> _p0;
  late final InputState _p1;
  late final FrameTime _p2;

  @override
  void initialize(World world) {
    world.ensureObjectStore<PlayerVisuals>();
    world.ensureTagStore<Player>();
    _p0 = Single<PlayerVisuals>(
      world.query1<PlayerVisuals>(
        withTypes: const <Type>[Player],
        withoutTypes: const <Type>[],
      ),
    );
    _p1 = world.resources.get<InputState>();
    _p2 = world.resources.get<FrameTime>();
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{}, writes: <Type>{PlayerVisuals});

  @override
  void run() {
    animateCrabLegs(_p0, _p1, _p2);
  }
}

/// Schedulable descriptor for [animateCrabLegs]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final animateCrabLegsSystem = SystemDescriptor(
  const SystemRef('package:scene_game/player/player.dart', 'animateCrabLegs'),
  () => $AnimateCrabLegsAdapter(),
);

mixin _$PlayerBundle implements SceneDashBundle {
  @override
  void insertInto(World world, Entity entity) {
    final self = this as PlayerBundle;
    world.ensureTagStore<Player>().add(entity.index);
    world.ensureObjectStore<SceneNodeRef>().insert(entity.index, self.node);
    world.ensureTagStore<PhysicsDriven>().add(entity.index);
    world.ensureObjectStore<PlayerVisuals>().insert(entity.index, self.visuals);
  }
}
