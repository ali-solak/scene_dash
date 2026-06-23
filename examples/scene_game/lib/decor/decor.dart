import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash/scene_dash.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import '../fx/instanced_pool.dart';
import '../game/config.dart';

part 'decor.g.dart';
part 'resources.dart';
part 'systems.dart';

/// Ambient decoration: many drifting light motes drawn as one [InstancedPool]
/// (one node, one draw call) instead of one entity/node per mote — the
/// data-oriented rendering path for homogeneous visuals.
@GamePlugin()
final class DecorPlugin extends Plugin {
  const DecorPlugin();

  @override
  void build(AppBuilder app) {
    app
      ..insertResource<MoteField>(MoteField())
      ..addSystem(spawnMotesSystem, schedule: Schedules.startup)
      ..addSystem(animateMotesSystem, schedule: Schedules.update);
  }
}
