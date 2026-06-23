part of 'rocks.dart';

/// A dynamic rock. Rapier owns its node transform, hence [PhysicsDriven].
@Bundle()
final class RockBundle with _$RockBundle {
  final Rock rock;
  final SceneNodeRef node;
  final PhysicsDriven physics;

  RockBundle({required double x, bool flaming = false})
    : rock = const Rock(),
      node = SceneNodeRef(_makeNode(x, flaming)),
      physics = const PhysicsDriven();

  static final Material _material = PhysicallyBasedMaterial()
    ..baseColorFactor = Vector4(0.42, 0.24, 0.18, 1)
    ..metallicFactor = 0.12
    ..roughnessFactor = 0.48;

  static final Material _flamingMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = Vector4(0.72, 0.22, 0.08, 1)
    ..emissiveFactor = Vector4(0.18, 0.04, 0.0, 1)
    ..metallicFactor = 0.18
    ..roughnessFactor = 0.26;

  static Node _makeNode(double x, bool flaming) {
    final node = Node(
      mesh: Mesh(SphereGeometry(radius: rockRadius), _material),
      localTransform: Matrix4.translation(Vector3(x, rockSpawnY, rockSpawnZ)),
    );
    if (flaming) {
      node.mesh = Mesh(SphereGeometry(radius: rockRadius), _flamingMaterial);
      // The flame trail is an ECS component + shared instanced pool (see
      // systems.dart), inserted on the entity by SpawnRocksSystem — not a
      // per-rock flutter_scene component here.
    }

    return node
      ..addComponent(
        RapierRigidBody(
          type: BodyType.dynamic_,
          ccdEnabled: true,
          linearVelocity: flaming
              ? Vector3(0, 0, flamingRockForwardVelocity)
              : Vector3.zero(),
          angularVelocity: flaming
              ? Vector3(flamingRockSpinVelocity, 0, 0)
              : Vector3.zero(),
        ),
      )
      ..addComponent(buildRockCollider());
  }
}

/// The collider for a rock, tagged with [PhysicsLayers.rock] so lose-condition
/// checks can classify a physics overlap hit by its collider layer instead of
/// rebuilding a set of every rock each frame. The collision *mask* stays
/// permissive (default) so rock contacts are unchanged.
RapierCollider buildRockCollider() => RapierCollider(
  shape: SphereShape(radius: rockRadius),
  collisionLayer: PhysicsLayers.rock,
);
