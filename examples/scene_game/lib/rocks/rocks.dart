import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash/scene_dash.dart';
import 'package:scene_dash_flutter_scene/scene_dash_flutter_scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../fx/instanced_pool.dart';
import '../game/config.dart';
import '../game/game_state.dart';

part 'rocks.g.dart';
part 'components.dart';
part 'resources.dart';
part 'bundles.dart';
part 'vfx.dart';
part 'systems.dart';

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
      ..addSystem(spawnRocksSystem, schedule: Schedules.fixedPrePhysics)
      ..addSystem(cleanupRocksSystem, schedule: Schedules.update)
      ..addSystem(updateRockTrailsSystem, schedule: Schedules.update);
  }
}
