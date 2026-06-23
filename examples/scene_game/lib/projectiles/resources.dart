part of 'projectiles.dart';

final class Blaster {
  double cooldown = 0;
  double burstTimer = 0;
  int queuedShots = 0;

  bool get canStartBurst => cooldown <= 0 && queuedShots == 0;

  void startBurst() {
    queuedShots = blasterBurstShots;
    burstTimer = 0;
    cooldown = blasterCooldown;
  }

  bool consumeShot(double dt) {
    if (cooldown > 0) {
      cooldown -= dt;
      if (cooldown < 0) cooldown = 0;
    }
    if (queuedShots == 0) return false;

    burstTimer -= dt;
    if (burstTimer > 0) return false;

    queuedShots--;
    burstTimer = blasterBurstInterval;
    return true;
  }

  void reset() {
    cooldown = 0;
    burstTimer = 0;
    queuedShots = 0;
  }
}

const int _sparkCapacity = 64;
const int _ringCapacity = 48;
const double _sparkDuration = 0.24;
const double _ringDuration = 0.34;

/// Pooled instanced impact VFX: a spark burst and a ground ring, each one
/// [InstancedPool] — one node, one draw call — instead of an entity + node +
/// material per hit. Pure data: the spawn/update systems own the build and the
/// animation; [emit] just records a hit into a recycled slot.
final class ImpactVfx {
  /// Built by `spawnImpactVfx`; null until then.
  InstancedPool? sparkPool;
  InstancedPool? ringPool;

  // Per-instance lifetime (seconds since emit; >= duration means free) and
  // packed origin (x, y, z), recycled round-robin via the cursors.
  final Float32List sparkAge = Float32List(_sparkCapacity)
    ..fillRange(0, _sparkCapacity, _sparkDuration);
  final Float32List sparkOrigin = Float32List(_sparkCapacity * 3);
  final Float32List ringAge = Float32List(_ringCapacity)
    ..fillRange(0, _ringCapacity, _ringDuration);
  final Float32List ringOrigin = Float32List(_ringCapacity * 3);
  int _sparkCursor = 0;
  int _ringCursor = 0;

  /// Fires a spark at [position] and a ground ring under it.
  void emit(Vector3 position) {
    _sparkCursor = _record(
      sparkAge,
      sparkOrigin,
      _sparkCursor,
      position.x,
      position.y,
      position.z,
    );
    _ringCursor = _record(
      ringAge,
      ringOrigin,
      _ringCursor,
      position.x,
      playerGroundYAtZ(position.z) + 0.03,
      position.z,
    );
  }
}

/// Records an emit into [cursor]'s slot and returns the next cursor.
int _record(
  Float32List age,
  Float32List origin,
  int cursor,
  double x,
  double y,
  double z,
) {
  age[cursor] = 0;
  origin[cursor * 3] = x;
  origin[cursor * 3 + 1] = y;
  origin[cursor * 3 + 2] = z;
  return (cursor + 1) % age.length;
}
