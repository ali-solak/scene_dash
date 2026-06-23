import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash/scene_dash.dart';
import 'package:scene_dash_flutter_scene/scene_dash_flutter_scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Ray, Vector3;

import '../game/camera_rig.dart';
import '../game/config.dart';
import '../game/game_state.dart';
import '../player/player.dart';
import '../rocks/rocks.dart';

part 'rules.g.dart';
part 'impact_motion.dart';
part 'systems.dart';

/// Installs the rules and restart systems. [GameState] is shared with the HUD.
@GamePlugin()
final class RulesPlugin extends Plugin {
  const RulesPlugin();

  @override
  void build(AppBuilder app) {
    app
      // RulesPlugin owns ImpactMotion: only its systems use it, so it is created
      // and registered here rather than in main().
      ..insertResource<ImpactMotion>(ImpactMotion())
      ..addSystem(restartSystem, schedule: Schedules.frameStart)
      ..addSystem(evaluateGameRulesSystem, schedule: Schedules.update)
      ..addSystem(playerViewSystem, schedule: Schedules.update);
  }
}
