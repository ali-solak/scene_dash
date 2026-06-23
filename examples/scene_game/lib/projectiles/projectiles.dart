import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash/scene_dash.dart';
import 'package:scene_dash_flutter_scene/scene_dash_flutter_scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../fx/instanced_pool.dart';
import '../game/config.dart';
import '../game/game_state.dart';
import '../player/player.dart';

part 'components.dart';
part 'projectiles.g.dart';
part 'resources.dart';
part 'bundles.dart';
part 'vfx.dart';
part 'systems.dart';

/// Installs the player's limited burst blaster.
@GamePlugin()
final class ProjectilesPlugin extends Plugin {
  const ProjectilesPlugin();

  @override
  void build(AppBuilder app) {
    app
      ..insertResource<Blaster>(Blaster())
      ..insertResource<ImpactVfx>(ImpactVfx())
      ..addSystem(shootProjectilesSystem, schedule: Schedules.fixedPrePhysics)
      ..addSystem(spawnImpactVfxSystem, schedule: Schedules.startup)
      ..addSystem(updateProjectilesSystem, schedule: Schedules.update)
      ..addSystem(updateImpactVfxSystem, schedule: Schedules.update);
  }
}
