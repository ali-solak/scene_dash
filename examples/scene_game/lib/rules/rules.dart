import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash/scene_dash.dart';
import 'package:scene_dash_flutter_scene/scene_dash_flutter_scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Ray, Vector3;

import '../collectables/collectables.dart';
import '../collectables/data/config.dart';
import '../game/camera_rig.dart';
import '../game/game_state.dart';
import '../game/physics_layers.dart';
import '../player/data/config.dart';
import '../player/player.dart';
import '../projectiles/projectiles.dart';
import '../rocks/rocks.dart';
import 'data/config.dart';

part 'rules.g.dart';
part 'systems/systems.dart';

/// Installs the rules and restart systems. [GameState] is shared with the HUD.
@GamePlugin()
final class RulesPlugin extends Plugin {
  const RulesPlugin();

  @override
  void build(AppBuilder app) {
    app
      ..addSystem(restartSystem, schedule: Schedules.frameStart)
      // The lose/deflect check must see this frame's collection and shield tick,
      // so order it explicitly behind those collectables systems (cross-feature
      // descriptors; a rename is a compile error).
      ..addSystem(
        evaluateGameRulesSystem,
        schedule: Schedules.update,
        after: [collectShieldPickupsSystem, updateShieldStateSystem],
        runIf: playing,
      )
      // Keep camera follow after rule evaluation so the view observes the latest
      // player state. Referencing the descriptor means a rename is a compile
      // error.
      ..addSystem(
        playerViewSystem,
        schedule: Schedules.update,
        after: [evaluateGameRulesSystem],
      );
  }
}
