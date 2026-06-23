import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash/scene_dash.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../game/config.dart';

part 'world.g.dart';

/// Installs world setup: lighting, post-processing, and the ramp.
@GamePlugin()
final class WorldPlugin extends Plugin {
  const WorldPlugin();

  @override
  void build(AppBuilder app) {
    app.addSystem(setupWorldSystem, schedule: Schedules.startup);
  }
}

/// Startup system: configures the scene look and builds the static ramp.
///
/// Scene-wide setup is native `flutter_scene` work done directly on the
/// `@Resource() Scene`. The ramp is a plain scene node, not an ECS entity: it
/// never moves, so it carries a fixed Rapier body and matching box collider.
@System()
final class SetupWorldSystem extends GameSystem {
  const SetupWorldSystem();

  void run(@Resource() Scene scene) {
    // Shadows and cross-stripes make the slope read clearly instead of as a
    // flat grey box.
    scene
      ..skybox = Skybox(GradientSkySource())
      ..environment = EnvironmentMap.studio()
      ..directionalLight = DirectionalLight(
        direction: Vector3(-0.45, -1.0, -0.35),
        color: Vector3(1.0, 0.94, 0.84),
        intensity: 4.4,
        castsShadow: true,
      )
      ..toneMapping = ToneMappingMode.aces
      ..exposure = 1.06;
    scene.postProcess.colorGrading
      ..enabled = true
      ..contrast = 1.04
      ..saturation = 1.05
      ..temperature = 0.08;
    scene.postProcess.bloom
      ..enabled = false
      ..threshold = 1.55
      ..intensity = 0.12
      ..scatter = 0.45;
    scene.postProcess.vignette
      ..enabled = true
      ..intensity = 0.24
      ..radius = 0.82
      ..smoothness = 0.62;

    // New flutter_scene 0.18 render knobs need no bridge code — they are plain
    // properties on the injected `@Resource() Scene`:
    scene
      // MSAA where the backend supports it, FXAA otherwise (the default).
      ..antiAliasingMode = AntiAliasingMode.auto
      // 1.0 = native resolution; <1.0 trades sharpness for speed, >1.0 supersamples.
      ..renderScale = 1.0;
    // Screen-space ambient occlusion grounds the player/rocks in the ramp's
    // creases (off by default; requires the PerspectiveCamera this game uses).
    scene.ambientOcclusion
      ..enabled = true
      ..intensity = 1.1
      ..radius = 0.4;

    final ramp =
        Node(
            mesh: Mesh(
              CuboidGeometry(Vector3(rampWidth, rampThickness, rampLength)),
              PhysicallyBasedMaterial()
                ..baseColorFactor = Vector4(0.24, 0.27, 0.32, 1)
                ..metallicFactor = 0.22
                ..roughnessFactor = 0.36,
            ),
            localTransform: Matrix4.rotationX(rampInclineRadians),
          )
          ..addComponent(RapierRigidBody(type: BodyType.fixed))
          ..addComponent(
            RapierCollider(
              shape: BoxShape(
                halfExtents: Vector3(
                  rampWidth / 2,
                  rampThickness / 2,
                  rampLength / 2,
                ),
              ),
            ),
          );

    _addLaneStripes(ramp);
    scene.root.add(ramp);
  }

  /// Bright cross-stripes painted on the ramp surface.
  void _addLaneStripes(Node ramp) {
    final stripe = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.9, 0.85, 0.5, 1)
      ..metallicFactor = 0.08
      ..roughnessFactor = 0.24
      ..emissiveFactor = Vector4(0.28, 0.22, 0.07, 1);
    const count = 7;
    final geometry = CuboidGeometry(Vector3(rampWidth * 0.94, 0.06, 0.35));
    for (var i = 1; i < count; i++) {
      final z = -rampLength / 2 + rampLength * i / count;
      ramp.add(
        Node(
          mesh: Mesh(geometry, stripe),
          localTransform: Matrix4.translation(
            Vector3(0, rampThickness / 2 + 0.04, z),
          ),
        ),
      );
    }
  }
}
