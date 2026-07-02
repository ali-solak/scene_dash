part of '../player.dart';

/// Player-owned shove state. Rules decide when a rock has contacted the player;
/// the player feature decides how that contact becomes controller movement.
final class PlayerKnockback {
  final Vector3 _velocity = Vector3.zero();
  final Vector3 _displacement = Vector3.zero();
  double _fallVelocityY = 0;

  /// Adds a shove away from the rock, falling back to down-ramp when centres
  /// overlap closely enough that the contact direction is ambiguous.
  void pushFromRock({
    required Vector3 playerPosition,
    required Vector3 rockPosition,
  }) {
    _velocity
      ..setFrom(playerPosition)
      ..sub(rockPosition)
      ..y = 0;
    if (_velocity.length2 < 0.001) {
      _velocity.setValues(0, 0, 1);
    } else {
      _velocity.normalize();
    }
    _velocity.scale(knockbackPushSpeed);
  }

  /// Returns this fixed step's horizontal displacement and damps the stored
  /// shove. Falling is handled separately once the player leaves the ramp.
  ///
  /// The returned vector is owned by this resource and rewritten by the next
  /// [step] call; consume it within the same step.
  Vector3 step(double dt) {
    if (_velocity.length2 < 0.0001) {
      _velocity.setZero();
      return _displacement..setZero();
    }

    _displacement
      ..setFrom(_velocity)
      ..scale(dt);
    final speed = _velocity.length;
    final nextSpeed = (speed - knockbackDecayRate * dt).clamp(0.0, speed);
    if (nextSpeed == 0) {
      _velocity.setZero();
    } else {
      _velocity.scale(nextSpeed / speed);
    }
    return _displacement;
  }

  /// Returns this fixed step's falling displacement while off the ramp.
  double fallStep(double dt) {
    _fallVelocityY -= gravityStrength * dt;
    return _fallVelocityY * dt;
  }

  /// The controller has grounded the player on the ramp.
  void ground() => _fallVelocityY = 0;

  void reset() {
    _velocity.setZero();
    _fallVelocityY = 0;
  }
}
