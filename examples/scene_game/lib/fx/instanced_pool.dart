import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

/// A fixed-capacity [InstancedMesh] pool: **one node, one draw call** for many
/// identical visuals (motes, sparks, trail puffs), animated allocation-free by
/// writing per-instance transforms through a single reusable [scratch] matrix.
///
/// This is the shared primitive behind the game's instanced VFX. Each feature
/// owns a pool (in its resource), builds it at startup with [addTo], then writes
/// transforms each frame; unused slots sit hidden off-screen via [hide].
///
/// 0.18 instancing carries a per-instance transform only (no per-instance
/// colour), so fades are done with scale and the material is shared by the pool.
final class InstancedPool {
  /// Creates a pool of [capacity] instances of [geometry] shaded by [material],
  /// all initially hidden.
  InstancedPool({
    required Geometry geometry,
    required Material material,
    required this.capacity,
  }) : mesh = InstancedMesh(geometry: geometry, material: material) {
    for (var i = 0; i < capacity; i++) {
      mesh.addInstance(_hidden);
    }
  }

  /// The instanced mesh; write to it with `setInstanceTransform(index, scratch)`.
  final InstancedMesh mesh;

  /// Number of instances in the pool.
  final int capacity;

  /// One transform, reused for every write and every frame. Mutate it in place
  /// (`setIdentity`, `setTranslationRaw`, `scaleByDouble`, ...) then pass it to
  /// `mesh.setInstanceTransform`.
  final Matrix4 scratch = Matrix4.identity();

  /// Adds the pool's single node under the scene root. Frustum culling is off:
  /// the instances move every frame, so a per-frame aggregate-bounds recompute
  /// would be wasted work.
  void addTo(Scene scene) {
    scene.root.add(
      Node()
        ..addComponent(InstancedMeshComponent(mesh))
        ..frustumCulled = false,
    );
  }

  /// Hides the instance at [index] by moving it far off-screen.
  void hide(int index) => mesh.setInstanceTransform(index, _hidden);
}

final Matrix4 _hidden = Matrix4.translation(Vector3(0, -9999, 0));
