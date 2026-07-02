import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash/scene_dash.dart';
import 'package:scene_dash_flutter_scene/scene_dash_flutter_scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../fx/instanced_pool.dart';
import '../game/game_state.dart';
import '../game/physics_layers.dart';
import 'data/config.dart';

part 'rocks.g.dart';
part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'vfx/vfx.dart';
part 'systems/systems.dart';

/// Installs the rocks feature and its spawner resource.
@GamePlugin()
final class RocksPlugin extends Plugin {
  const RocksPlugin();

  @override
  void build(AppBuilder app) {
    app
      ..insertResource<RockSpawner>(RockSpawner())
      ..insertResource<RockTrails>(RockTrails())
      ..addSystem(spawnRockTrailsSystem, schedule: Schedules.startup)
      ..addSystem(
        spawnRocksSystem,
        schedule: Schedules.fixedPrePhysics,
        runIf: playing,
      )
      ..addSystem(cleanupRocksSystem, schedule: Schedules.update)
      ..addSystem(updateRockHitReactionsSystem, schedule: Schedules.update)
      ..addSystem(updateRockTrailsSystem, schedule: Schedules.update);
  }
}
