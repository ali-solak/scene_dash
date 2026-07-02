part of '../player.dart';

/// Startup: spawn the one player. A top-level `@System` function — the most
/// concise system form (no class, no constructor, no mixin). The generator emits
/// a `spawnPlayerSystem` descriptor for it.
@System()
void spawnPlayer(Commands commands) {
  commands.spawn(PlayerBundle());
}

/// Fixed step: translate input into a move-and-slide request.
///
/// Drives the player through its native character controller and snaps it to the
/// ramp (both reached through `SceneNodeRef`), so the query declares
/// `writes: [SceneNodeRef]`: mutating an object reached through a component
/// reference counts as writing that component for scheduler diagnostics.
@System()
void movePlayer(
  @Query(requires: [Player], writes: [SceneNodeRef])
  Single<SceneNodeRef> player,
  @Resource() InputState input,
  @Resource() FixedTime time,
  @Resource() PlayerKnockback knockback,
) {
  // The integration mounts the player under the RapierWorld before the first
  // step, so the node is already in the scene here. Resolve the Single once
  // (`.value` re-runs the query each access) and reach the native controller
  // through `SceneNodeRef.component`.
  final ref = player.value;
  final controller = ref.component<RapierKinematicCharacterController>();
  if (controller == null) return;

  final node = ref.node;
  final dt = time.delta;
  _snapToRamp(node, knockback);

  // Read the translation straight out of the column-major matrix storage
  // (elements 12..14) instead of getTranslation(), which allocates.
  final m = node.localTransform.storage;
  final positionY = m[13];
  final motion = knockback.step(dt)
    ..x += input.horizontal * playerStrafeSpeed * dt;
  final nextX = m[12] + motion.x;
  final nextZ = m[14] + motion.z;
  if (isOverRampFootprint(nextX, nextZ)) {
    motion.y = playerGroundYAtZ(nextZ) - positionY;
    knockback.ground();
  } else {
    motion.y += knockback.fallStep(dt);
  }
  controller.move(motion);
}

void _snapToRamp(Node node, PlayerKnockback knockback) {
  final transform = node.localTransform;
  final m = transform.storage;
  if (!isOverRampFootprint(m[12], m[14])) return;
  m[13] = playerGroundYAtZ(m[14]);
  // Reassign to trip the transform dirty flag after the in-place edit.
  node.localTransform = transform;
  knockback.ground();
}

/// Update: unfold the six visual crab legs, then layer a procedural two-group
/// gait on top while the player strafes. Only player-owned child nodes move;
/// the physics/root node and the central collider remain untouched.
@System()
void animateCrabLegs(
  @Query(requires: [Player], writes: [PlayerVisuals])
  Single<PlayerVisuals> visuals,
  @Resource() InputState input,
  @Resource() FrameTime time,
) {
  final v = visuals.value;
  final dt = time.delta;

  v.legExtension01 = _approach01(
    v.legExtension01,
    1.0,
    dt / crabLegExtensionDuration,
  );

  final movement01 = input.horizontal.abs().clamp(0.0, 1.0).toDouble();
  v.gaitPhase = advanceCrabGaitPhase(v.gaitPhase, movement01, dt);
  final direction = input.horizontal == 0
      ? 1.0
      : input.horizontal.sign.toDouble();

  for (final leg in v.allLegs) {
    final sample = sampleCrabLegGait(
      globalExtension: v.legExtension01,
      extensionDelay: leg.extensionDelay,
      movement01: movement01,
      direction: direction,
      gaitPhase: v.gaitPhase,
      phaseOffset: leg.phaseOffset,
    );
    final basePose = _mixCrabLegPose(
      leg.collapsedPose,
      leg.extendedPose,
      sample.extension,
    );
    _applyLegPose(leg, basePose, sample.lift, sample.stride, sample.bend);
  }
}

double _approach01(double value, double target, double amount) {
  final a = amount.clamp(0.0, 1.0).toDouble();
  return value + (target - value) * a;
}
