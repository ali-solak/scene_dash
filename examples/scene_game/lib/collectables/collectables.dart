import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash/scene_dash.dart';
import 'package:scene_dash_flutter_scene/scene_dash_flutter_scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../fx/instanced_pool.dart';
import '../game/game_state.dart';
import '../game/physics_layers.dart';
import '../player/data/config.dart';
import '../player/player.dart';
import 'data/config.dart';

part 'collectables.g.dart';
part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'vfx/vfx.dart';
part 'systems/systems.dart';

/// Installs rolling shield pickups, the shield state, and the player's shield
/// feedback and deflection VFX.
///
/// [ShieldState] is constructed once in `main()` and shared with the HUD, so the
/// plugin receives it and is the sole place it is registered as a resource.
@GamePlugin()
final class CollectablesPlugin extends Plugin {
  const CollectablesPlugin({required this.shield});

  final ShieldState shield;

  @override
  void build(AppBuilder app) {
    app
      ..insertResource<ShieldState>(shield)
      ..insertResource<CollectableSpawner>(CollectableSpawner())
      ..insertResource<ShieldDeflectVfx>(ShieldDeflectVfx())
      // Spawn in fixedPrePhysics so the body is mounted before the native step,
      // under the existing command-boundary lifecycle.
      ..addSystem(
        spawnShieldPickupsSystem,
        schedule: Schedules.fixedPrePhysics,
        runIf: playing,
      )
      ..addSystem(spawnShieldDeflectVfxSystem, schedule: Schedules.startup)
      ..addSystem(
        updateShieldStateSystem,
        schedule: Schedules.update,
        runIf: playing,
      )
      ..addSystem(animateShieldPickupsSystem, schedule: Schedules.update)
      // Collection activates the shield; order it after the shield tick so a
      // freshly collected shield is not immediately ticked down this frame.
      ..addSystem(
        collectShieldPickupsSystem,
        schedule: Schedules.update,
        after: [updateShieldStateSystem],
        runIf: playing,
      )
      ..addSystem(
        updateShieldVisualsSystem,
        schedule: Schedules.update,
        after: [updateShieldStateSystem],
      )
      ..addSystem(cleanupPickupsSystem, schedule: Schedules.update)
      ..addSystem(updateShieldDeflectVfxSystem, schedule: Schedules.update);
  }
}
