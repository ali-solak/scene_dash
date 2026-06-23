part of 'projectiles.dart';

@Bundle()
final class ProjectileBundle with _$ProjectileBundle {
  ProjectileBundle({required Vector3 position})
    : projectile = Projectile(),
      node = SceneNodeRef(_makeNode(position));

  final Projectile projectile;
  final SceneNodeRef node;
  final PhysicsDriven physics = const PhysicsDriven();

  static final Material _material = PhysicallyBasedMaterial()
    ..baseColorFactor = Vector4(0.5, 0.9, 1.0, 1)
    ..emissiveFactor = Vector4(0.3, 0.85, 1.0, 1)
    ..metallicFactor = 0.08
    ..roughnessFactor = 0.18;

  static Node _makeNode(Vector3 position) {
    return Node(
        mesh: Mesh(SphereGeometry(radius: projectileRadius), _material),
        localTransform: Matrix4.translation(position),
      )
      ..frustumCulled = false
      ..add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: projectileRadius * 1.35),
            glowMaterial(Vector4(0.38, 0.9, 1.0, 0.42), alpha: 0.42),
          ),
        )..frustumCulled = false,
      )
      ..add(
        Node(
          mesh: Mesh(
            CuboidGeometry(Vector3(0.07, 0.07, 0.78)),
            glowMaterial(Vector4(0.18, 0.55, 1.0, 0.2), alpha: 0.2),
          ),
          localTransform: Matrix4.translation(Vector3(0, 0, 0.38)),
        )..frustumCulled = false,
      )
      ..addComponent(
        RapierRigidBody(
          type: BodyType.dynamic_,
          mass: 0.04,
          ccdEnabled: true,
          linearVelocity: Vector3(0, projectileLaunchUp, -projectileSpeed),
          linearDamping: 0,
        ),
      )
      ..addComponent(
        RapierCollider(
          shape: SphereShape(radius: projectileRadius),
          isTrigger: true,
        ),
      );
  }
}
