import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash/scene_dash.dart';
import 'package:scene_dash_flutter_scene/scene_dash_flutter_scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../game/game_state.dart';
import '../game/physics_layers.dart';
import '../world/data/config.dart';
import '../world/data/ramp.dart';
import 'data/config.dart';

part 'player.g.dart';
part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'systems/systems.dart';

/// Installs the player feature.
@GamePlugin()
final class PlayerPlugin extends Plugin {
  const PlayerPlugin();

  @override
  void build(AppBuilder app) {
    app
      ..insertResource<PlayerKnockback>(PlayerKnockback())
      ..addSystem(spawnPlayerSystem, schedule: Schedules.startup)
      ..addSystem(
        movePlayerSystem,
        schedule: Schedules.fixedPrePhysics,
        runIf: playing,
      )
      ..addSystem(
        animateCrabLegsSystem,
        schedule: Schedules.update,
        runIf: playing,
      );
  }
}
