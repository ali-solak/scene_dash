part of 'projectiles.dart';

@System()
final class ShootProjectilesSystem extends GameSystem {
  const ShootProjectilesSystem();

  void run(
    Commands commands,
    @Query(requires: [Player]) Query1<SceneNodeRef> players,
    @Resource() InputState input,
    @Resource() GameState game,
    @Resource() Blaster blaster,
    @Resource() FixedTime time,
  ) {
    if (game.status != GameStatus.playing) {
      input.shootRequested = false;
      blaster.reset();
      return;
    }

    if (input.shootRequested && blaster.canStartBurst) {
      blaster.startBurst();
    }
    input.shootRequested = false;

    if (!blaster.consumeShot(time.delta)) return;
    final player = players.singleOrNull();
    if (player == null) return;

    final position = player.$2.node.globalTransform.getTranslation()
      ..y += playerRadius * 0.45
      ..z -= playerRadius + projectileRadius + 0.08;
    commands.spawn(ProjectileBundle(position: position));
  }
}

@System()
final class UpdateProjectilesSystem extends GameSystem {
  const UpdateProjectilesSystem();

  void run(
    @Query(writes: [Projectile]) Query2<Projectile, SceneNodeRef> projectiles,
    @Resource() PhysicsWorld physics,
    @Resource() ImpactVfx vfx,
    @Resource() FrameTime time,
    Commands commands,
  ) {
    final dt = time.delta;
    projectiles.each((entity, projectile, binding) {
      projectile.age += dt;
      final position = binding.node.globalTransform.getTranslation();

      if (projectile.age >= projectileLifetime ||
          position.z < -rampLength * 0.5 - 2 ||
          position.y < -2) {
        commands.despawn(entity);
        return;
      }

      if (_knockFirstRock(physics, position)) {
        // Fire pooled instanced VFX instead of spawning per-hit entities/nodes.
        vfx.emit(position);
        commands.despawn(entity);
      }
    });
  }

  bool _knockFirstRock(PhysicsWorld physics, Vector3 position) {
    final hits = physics.overlapSphere(
      position,
      projectileHitRadius,
      layerMask: PhysicsLayers.rock,
      includeFixed: false,
      includeKinematic: false,
      includeDynamic: true,
      includeTriggers: false,
    );
    for (final hit in hits) {
      final collider = hit.collider;
      if (collider is! RapierCollider ||
          collider.collisionLayer & PhysicsLayers.rock == 0) {
        continue;
      }

      final rockPosition = hit.node.globalTransform.getTranslation();
      final xAway = rockPosition.x - position.x;
      final body = hit.node.getComponent<RapierRigidBody>();
      if (body != null) {
        body.linearVelocity = Vector3(
          xAway.clamp(-1, 1).toDouble() * projectileKnockback * 0.35,
          projectileLift,
          -projectileKnockback,
        );
        body.angularVelocity = Vector3(-9, 0, xAway.sign * 5);
      }
      return true;
    }
    return false;
  }
}

/// Startup: build the spark and ring instanced pools and add their nodes.
@System()
void spawnImpactVfx(@Resource() Scene scene, @Resource() ImpactVfx vfx) {
  vfx.sparkPool = InstancedPool(
    geometry: SphereGeometry(radius: 0.22, segments: 12, rings: 6),
    material: glowMaterial(Vector4(0.56, 0.92, 1.0, 0.4), alpha: 0.4),
    capacity: _sparkCapacity,
  )..addTo(scene);
  vfx.ringPool = InstancedPool(
    geometry: ringGeometry(thickness: 0.16),
    material: glowMaterial(Vector4(0.44, 0.82, 1.0, 0.28), alpha: 0.28),
    capacity: _ringCapacity,
  )..addTo(scene);
}

/// Update: advance both pools. Allocation-free — one scratch matrix per pool,
/// reused for every instance. 0.18 instancing is transform-only, so the fade is
/// scale-based: each puff grows toward its end scale, then shrinks to nothing.
@System()
void updateImpactVfx(@Resource() ImpactVfx vfx, @Resource() FrameTime time) {
  final dt = time.delta;
  _advanceBurst(
    vfx.sparkPool,
    vfx.sparkAge,
    vfx.sparkOrigin,
    dt,
    duration: _sparkDuration,
    startScale: 0.45,
    endScale: 1.15,
    floatUp: 0.3,
    spin: 0.8,
  );
  _advanceBurst(
    vfx.ringPool,
    vfx.ringAge,
    vfx.ringOrigin,
    dt,
    duration: _ringDuration,
    startScale: 0.4,
    endScale: 1.8,
    spin: 0.7,
  );
}

/// Advances one burst pool: ages each live instance and writes its grow-then-pop
/// transform; free slots (age past [duration]) are skipped (already hidden).
void _advanceBurst(
  InstancedPool? pool,
  Float32List age,
  Float32List origin,
  double dt, {
  required double duration,
  required double startScale,
  required double endScale,
  double floatUp = 0,
  double spin = 0,
}) {
  if (pool == null) return;
  final scratch = pool.scratch;
  for (var i = 0; i < age.length; i++) {
    final a = age[i];
    if (a >= duration) continue;
    final next = a + dt;
    age[i] = next;
    final t = (next / duration).clamp(0.0, 1.0);
    final ease = 1 - math.pow(1 - t, 3).toDouble();
    final fade = (1 - t) * (1 - t);
    final s = (startScale + (endScale - startScale) * ease) * fade;
    scratch
      ..setIdentity()
      ..setTranslationRaw(
        origin[i * 3],
        origin[i * 3 + 1] + floatUp * ease,
        origin[i * 3 + 2],
      )
      ..rotateY(spin * t)
      ..scaleByDouble(s, s, s, 1);
    pool.mesh.setInstanceTransform(i, scratch);
  }
}
