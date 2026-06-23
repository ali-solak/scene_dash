import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_flutter_scene/scene_dash_flutter_scene.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'decor/decor.dart';
import 'game/camera.dart';
import 'game/camera_rig.dart';
import 'game/config.dart';
import 'game/game_state.dart';
import 'hud/game_hud.dart';
import 'player/player.dart';
import 'projectiles/projectiles.dart';
import 'rocks/rocks.dart';
import 'rules/rules.dart';
import 'world/world.dart';

/// Rock Dodge: an inclined platform, rolling rocks, and one player sphere.
///
/// The game is structured as Scene-Dash features (`world/`, `player/`,
/// `rocks/`, `rules/`), each a plugin with its own systems. Physics is native
/// `flutter_scene_rapier`; bundles attach real bodies and colliders to scene
/// nodes, while ECS systems steer and query those native objects.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Scene.initializeStaticResources();

  final scene = Scene();

  final physics = RapierWorld(gravity: Vector3(0, -gravityStrength, 0));
  scene.root.addComponent(physics);

  final input = InputState();
  final gameState = GameState();
  final hudState = HudState(gameState);
  final cameraRig = CameraRig();

  // Resources the Flutter widget also holds are constructed here and inserted
  // once through the game;
  final game = Game(scene: scene)
    ..addPlugin(PhysicsPlugin(physics))
    ..addPlugin(const WorldPlugin())
    ..addPlugin(const PlayerPlugin())
    ..addPlugin(const ProjectilesPlugin())
    ..addPlugin(const RocksPlugin())
    ..addPlugin(const RulesPlugin())
    ..addPlugin(const DecorPlugin())
    ..insertResource<InputState>(input)
    ..insertResource<GameState>(gameState)
    ..insertResource<CameraRig>(cameraRig);

  await game.start();

  runApp(
    RockDodgeApp(
      scene: scene,
      game: game,
      input: input,
      gameState: gameState,
      hudState: hudState,
      cameraRig: cameraRig,
    ),
  );
}

class RockDodgeApp extends StatefulWidget {
  const RockDodgeApp({
    super.key,
    required this.scene,
    required this.game,
    required this.input,
    required this.gameState,
    required this.hudState,
    required this.cameraRig,
  });

  final Scene scene;
  final Game game;
  final InputState input;
  final GameState gameState;
  final HudState hudState;
  final CameraRig cameraRig;

  @override
  State<RockDodgeApp> createState() => _RockDodgeAppState();
}

class _RockDodgeAppState extends State<RockDodgeApp> {
  final FocusNode _focus = FocusNode();
  final Set<LogicalKeyboardKey> _pressed = <LogicalKeyboardKey>{};

  bool _touchLeft = false;
  bool _touchRight = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _pressed.add(event.logicalKey);
      if (event.logicalKey == LogicalKeyboardKey.keyR) {
        widget.input.restartRequested = true;
      } else if (event.logicalKey == LogicalKeyboardKey.space) {
        widget.input.shootRequested = true;
      }
    } else if (event is KeyUpEvent) {
      _pressed.remove(event.logicalKey);
    }
    _syncHorizontalInput();
    return KeyEventResult.handled;
  }

  void _setTouchLeft(bool value) {
    _touchLeft = value;
    _syncHorizontalInput();
  }

  void _setTouchRight(bool value) {
    _touchRight = value;
    _syncHorizontalInput();
  }

  void _requestRestart() {
    _touchLeft = false;
    _touchRight = false;
    widget.input
      ..horizontal = 0
      ..restartRequested = true;
  }

  void _requestShoot() {
    widget.input.shootRequested = true;
  }

  void _syncHorizontalInput() {
    final keyLeft =
        _pressed.contains(LogicalKeyboardKey.arrowLeft) ||
        _pressed.contains(LogicalKeyboardKey.keyA);
    final keyRight =
        _pressed.contains(LogicalKeyboardKey.arrowRight) ||
        _pressed.contains(LogicalKeyboardKey.keyD);
    final left = keyLeft || _touchLeft;
    final right = keyRight || _touchRight;
    widget.input.horizontal = (left ? 1.0 : 0.0) - (right ? 1.0 : 0.0);
  }

  void _onTick(Duration elapsed, double deltaSeconds) {
    widget.game.onTick(elapsed, deltaSeconds);
    widget.hudState.recordFrame(deltaSeconds);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SceneView(
                widget.scene,
                cameraBuilder: (elapsed) =>
                    buildGameCamera(elapsed, widget.cameraRig),
                onTick: _onTick,
              ),
              GameHud(
                hud: widget.hudState,
                onLeftChanged: _setTouchLeft,
                onRightChanged: _setTouchRight,
                onShoot: _requestShoot,
                onRestart: _requestRestart,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
