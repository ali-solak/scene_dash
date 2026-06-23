import 'package:flutter_scene/scene.dart' show Node;
import 'package:scene_dash/scene_dash.dart';

import 'scene_commands.dart';
import 'scene_node_ref.dart';

/// Keeps the scene graph in sync with entity-bound [SceneNodeRef]s: mounts new
/// nodes and detaches them again when their entity goes away.
///
/// Each run it reconciles the set of bound nodes against the scene:
///
/// * a newly bound node with no parent is queued under the scene root (through
///   [SceneCommands]) and remembered;
/// * a node the integration previously mounted whose binding has gone — the
///   entity was despawned, the [SceneNodeRef] was removed, or it was replaced
///   with a different node — is queued for detachment.
///
/// A node the game parents itself (custom hierarchy) is never adopted and never
/// auto-detached: only nodes this adapter mounted are tracked. This makes the
/// common case — `commands.spawn(bundle)` then later `commands.despawn(entity)`
/// — clean up its scene node automatically, with no manual `SceneCommands.remove`
/// in game code.
///
/// It also maintains the integration-managed [Mounted] tag: each mounted entity
/// gains [Mounted] and loses it on unmount, so advanced systems can filter on
/// scene-mounted entities.
///
/// [Game] runs this *before* the `update` phase each frame (and once at startup),
/// so a bound node is already parented and tagged by the time gameplay reads it.
final class SceneNodeMountAdapter implements SystemAdapter {
  final SceneCommands _sceneCommands;

  /// Live node → entity index shared with the `SceneNodeIndex` resource. Updated
  /// from this adapter's existing per-frame scan over bound nodes, so the reverse
  /// lookup costs no extra allocation.
  final Map<Node, Entity> _index;

  late final World _world;
  late final Query1<SceneNodeRef> _bound;

  /// Nodes this adapter mounted, mapped to the entity they were mounted for.
  final Map<Node, Entity> _mounted = <Node, Entity>{};

  /// Scratch set of nodes seen this run (reused to avoid per-frame allocation).
  final Set<Node> _seen = <Node>{};

  /// Scratch lists of entities to (un)tag, applied after the bound query stops
  /// iterating (tag stores cannot be mutated mid-query). Reused each run.
  final List<Entity> _toTag = <Entity>[];
  final List<Entity> _toUntag = <Entity>[];

  SceneNodeMountAdapter(this._sceneCommands, this._index);

  @override
  void initialize(World world) {
    _world = world;
    world
      ..ensureObjectStore<SceneNodeRef>()
      ..ensureTagStore<Mounted>();
    _bound = world.query1<SceneNodeRef>();
  }

  @override
  void run() {
    _seen.clear();
    _toTag.clear();
    _toUntag.clear();
    _bound.each((entity, binding) {
      final node = binding.node;
      _seen.add(node);
      // Maintain the reverse node -> entity index for every bound node (not just
      // ones we mount), so picking can resolve any visible node to its entity.
      _index[node] = entity;
      if (_mounted.containsKey(node)) return;
      // Adopt only nodes that have no parent yet; a node the game parented
      // itself is left alone (and never tracked for auto-detach).
      if (node.parent == null) {
        _sceneCommands.add(node);
        _mounted[node] = entity;
        _toTag.add(entity);
      }
    });
    // Detach nodes we mounted whose binding disappeared (despawn, component
    // removal, or replacement with a different node).
    _mounted.removeWhere((node, entity) {
      if (_seen.contains(node)) return false;
      _sceneCommands.remove(node);
      _toUntag.add(entity);
      return true;
    });
    // Prune index entries whose node is no longer bound (despawn, component
    // removal, or replacement). Reuses the scan's _seen set, no allocation.
    _index.removeWhere((node, _) => !_seen.contains(node));

    // Apply Mounted-tag changes now the bound query is no longer iterating.
    // Untag first so a same-entity node replacement (untag old, tag new) ends
    // up tagged. Despawn already strips the tag, so only touch live entities.
    final mounted = _world.ensureTagStore<Mounted>();
    for (final entity in _toUntag) {
      if (_world.isAlive(entity)) mounted.removeEntityIndex(entity.index);
    }
    for (final entity in _toTag) {
      if (_world.isAlive(entity)) mounted.add(entity.index);
    }
  }
}
