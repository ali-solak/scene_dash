// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'decor.dart';

// **************************************************************************
// EcsGenerator
// **************************************************************************

class $SpawnMotesAdapter implements SystemAdapter, SystemAccessProvider {
  late final Scene _p0;
  late final MoteField _p1;

  @override
  void initialize(World world) {
    _p0 = world.resources.get<Scene>();
    _p1 = world.resources.get<MoteField>();
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{}, writes: <Type>{});

  @override
  void run() {
    spawnMotes(_p0, _p1);
  }
}

/// Schedulable descriptor for [spawnMotes]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final spawnMotesSystem = SystemDescriptor(
  const SystemRef('package:scene_game/decor/decor.dart', 'spawnMotes'),
  () => $SpawnMotesAdapter(),
);

class $AnimateMotesAdapter implements SystemAdapter, SystemAccessProvider {
  late final MoteField _p0;
  late final FrameTime _p1;

  @override
  void initialize(World world) {
    _p0 = world.resources.get<MoteField>();
    _p1 = world.resources.get<FrameTime>();
  }

  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{}, writes: <Type>{});

  @override
  void run() {
    animateMotes(_p0, _p1);
  }
}

/// Schedulable descriptor for [animateMotes]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final animateMotesSystem = SystemDescriptor(
  const SystemRef('package:scene_game/decor/decor.dart', 'animateMotes'),
  () => $AnimateMotesAdapter(),
);
