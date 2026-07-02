// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collectables.dart';

// **************************************************************************
// EcsGenerator
// **************************************************************************

class $SpawnShieldPickupsAdapter
    implements SystemAdapter, SystemAccessProvider {
  late final OptionalSingle<SceneNodeRef> _p0;
  late final CollectableSpawner _p1;
  late final FixedTime _p2;
  late final Commands _p3;

  @override
  void initialize(World world) {
    world.ensureObjectStore<SceneNodeRef>();
    world.ensureTagStore<ShieldPickup>();
    _p0 = OptionalSingle<SceneNodeRef>(
      world.query1<SceneNodeRef>(
        withTypes: const <Type>[ShieldPickup],
        withoutTypes: const <Type>[],
      ),
    );
    _p1 = world.resources.get<CollectableSpawner>();
    _p2 = world.resources.get<FixedTime>();
    _p3 = world.commands;
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{SceneNodeRef}, writes: <Type>{});

  @override
  void run() {
    spawnShieldPickups(_p0, _p1, _p2, _p3);
  }
}

/// Schedulable descriptor for [spawnShieldPickups]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final spawnShieldPickupsSystem = SystemDescriptor(
  const SystemRef(
    'package:scene_game/collectables/collectables.dart',
    'spawnShieldPickups',
  ),
  () => $SpawnShieldPickupsAdapter(),
);

class $UpdateShieldStateAdapter implements SystemAdapter, SystemAccessProvider {
  late final ShieldState _p0;
  late final FrameTime _p1;

  @override
  void initialize(World world) {
    _p0 = world.resources.get<ShieldState>();
    _p1 = world.resources.get<FrameTime>();
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{}, writes: <Type>{});

  @override
  void run() {
    updateShieldState(_p0, _p1);
  }
}

/// Schedulable descriptor for [updateShieldState]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final updateShieldStateSystem = SystemDescriptor(
  const SystemRef(
    'package:scene_game/collectables/collectables.dart',
    'updateShieldState',
  ),
  () => $UpdateShieldStateAdapter(),
);

class $AnimateShieldPickupsAdapter
    implements SystemAdapter, SystemAccessProvider {
  late final Query2<ShieldPickupState, ShieldPickupVisuals> _p0;
  late final FrameTime _p1;

  @override
  void initialize(World world) {
    world.ensureObjectStore<ShieldPickupState>();
    world.ensureObjectStore<ShieldPickupVisuals>();
    world.ensureTagStore<ShieldPickup>();
    _p0 = world.query2<ShieldPickupState, ShieldPickupVisuals>(
      withTypes: const <Type>[ShieldPickup],
      withoutTypes: const <Type>[],
    );
    _p1 = world.resources.get<FrameTime>();
  }

  @override
  SystemAccess get access => const SystemAccess(
    reads: <Type>{},
    writes: <Type>{ShieldPickupState, ShieldPickupVisuals},
  );

  @override
  void run() {
    animateShieldPickups(_p0, _p1);
  }
}

/// Schedulable descriptor for [animateShieldPickups]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final animateShieldPickupsSystem = SystemDescriptor(
  const SystemRef(
    'package:scene_game/collectables/collectables.dart',
    'animateShieldPickups',
  ),
  () => $AnimateShieldPickupsAdapter(),
);

class $CollectShieldPickupsAdapter
    implements SystemAdapter, SystemAccessProvider {
  late final Single<SceneNodeRef> _p0;
  late final Query1<SceneNodeRef> _p1;
  late final ShieldState _p2;
  late final Commands _p3;

  @override
  void initialize(World world) {
    world.ensureObjectStore<SceneNodeRef>();
    world.ensureTagStore<Player>();
    world.ensureTagStore<ShieldPickup>();
    _p0 = Single<SceneNodeRef>(
      world.query1<SceneNodeRef>(
        withTypes: const <Type>[Player],
        withoutTypes: const <Type>[],
      ),
    );
    _p1 = world.query1<SceneNodeRef>(
      withTypes: const <Type>[ShieldPickup],
      withoutTypes: const <Type>[],
    );
    _p2 = world.resources.get<ShieldState>();
    _p3 = world.commands;
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{SceneNodeRef}, writes: <Type>{});

  @override
  void run() {
    collectShieldPickups(_p0, _p1, _p2, _p3);
  }
}

/// Schedulable descriptor for [collectShieldPickups]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final collectShieldPickupsSystem = SystemDescriptor(
  const SystemRef(
    'package:scene_game/collectables/collectables.dart',
    'collectShieldPickups',
  ),
  () => $CollectShieldPickupsAdapter(),
);

class $UpdateShieldVisualsAdapter
    implements SystemAdapter, SystemAccessProvider {
  late final Single<PlayerVisuals> _p0;
  late final ShieldState _p1;
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
    _p1 = world.resources.get<ShieldState>();
    _p2 = world.resources.get<FrameTime>();
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{}, writes: <Type>{PlayerVisuals});

  @override
  void run() {
    updateShieldVisuals(_p0, _p1, _p2);
  }
}

/// Schedulable descriptor for [updateShieldVisuals]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final updateShieldVisualsSystem = SystemDescriptor(
  const SystemRef(
    'package:scene_game/collectables/collectables.dart',
    'updateShieldVisuals',
  ),
  () => $UpdateShieldVisualsAdapter(),
);

class $CleanupPickupsAdapter implements SystemAdapter, SystemAccessProvider {
  late final Query1<SceneNodeRef> _p0;
  late final Commands _p1;

  @override
  void initialize(World world) {
    world.ensureObjectStore<SceneNodeRef>();
    world.ensureTagStore<Collectable>();
    _p0 = world.query1<SceneNodeRef>(
      withTypes: const <Type>[Collectable],
      withoutTypes: const <Type>[],
    );
    _p1 = world.commands;
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{SceneNodeRef}, writes: <Type>{});

  @override
  void run() {
    cleanupPickups(_p0, _p1);
  }
}

/// Schedulable descriptor for [cleanupPickups]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final cleanupPickupsSystem = SystemDescriptor(
  const SystemRef(
    'package:scene_game/collectables/collectables.dart',
    'cleanupPickups',
  ),
  () => $CleanupPickupsAdapter(),
);

class $SpawnShieldDeflectVfxAdapter
    implements SystemAdapter, SystemAccessProvider {
  late final Scene _p0;
  late final ShieldDeflectVfx _p1;

  @override
  void initialize(World world) {
    _p0 = world.resources.get<Scene>();
    _p1 = world.resources.get<ShieldDeflectVfx>();
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{}, writes: <Type>{});

  @override
  void run() {
    spawnShieldDeflectVfx(_p0, _p1);
  }
}

/// Schedulable descriptor for [spawnShieldDeflectVfx]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final spawnShieldDeflectVfxSystem = SystemDescriptor(
  const SystemRef(
    'package:scene_game/collectables/collectables.dart',
    'spawnShieldDeflectVfx',
  ),
  () => $SpawnShieldDeflectVfxAdapter(),
);

class $UpdateShieldDeflectVfxAdapter
    implements SystemAdapter, SystemAccessProvider {
  late final ShieldDeflectVfx _p0;
  late final FrameTime _p1;

  @override
  void initialize(World world) {
    _p0 = world.resources.get<ShieldDeflectVfx>();
    _p1 = world.resources.get<FrameTime>();
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{}, writes: <Type>{});

  @override
  void run() {
    updateShieldDeflectVfx(_p0, _p1);
  }
}

/// Schedulable descriptor for [updateShieldDeflectVfx]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final updateShieldDeflectVfxSystem = SystemDescriptor(
  const SystemRef(
    'package:scene_game/collectables/collectables.dart',
    'updateShieldDeflectVfx',
  ),
  () => $UpdateShieldDeflectVfxAdapter(),
);

mixin _$ShieldPickupBundle implements SceneDashBundle {
  @override
  void insertInto(World world, Entity entity) {
    final self = this as ShieldPickupBundle;
    world.ensureTagStore<Collectable>().add(entity.index);
    world.ensureTagStore<ShieldPickup>().add(entity.index);
    world.ensureObjectStore<ShieldPickupState>().insert(
      entity.index,
      self.state,
    );
    world.ensureObjectStore<ShieldPickupVisuals>().insert(
      entity.index,
      self.visuals,
    );
    world.ensureObjectStore<SceneNodeRef>().insert(entity.index, self.node);
    world.ensureTagStore<PhysicsDriven>().add(entity.index);
  }
}
