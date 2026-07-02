import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:scene_dash_generator/builder.dart';
import 'package:test/test.dart';

const _imports = "import 'package:scene_dash/scene_dash.dart';\n";

const _inputId = 'pkg|lib/input.dart';
const _outputId = 'pkg|lib/input.scene_dash.g.part';
const _stubId = 'scene_dash|lib/scene_dash.dart';

// `testBuilder` reads non-root package sources from its in-memory reader (real
// pub-cache sources are not consulted), so we provide a minimal stub of the
// scene_dash public API for the input to resolve against. The generator only
// needs the annotations (and a few referenced types) to resolve; the generated
// output is asserted as text and never compiled here.
const _sceneDashStub = '''
class PackedComponent { const PackedComponent(); }
class ObjectComponent { const ObjectComponent(); }
class Tag { const Tag(); }
class Bundle { const Bundle(); }
class System { const System(); }
class Resource { const Resource(); }
class GamePlugin {
  final List<Type> requires;
  const GamePlugin({this.requires = const []});
}
class Query {
  final List<Type> writes;
  final List<Type> requires;
  final List<Type> excludes;
  const Query({this.writes = const [], this.requires = const [], this.excludes = const []});
}

class Entity {}
class World {}
class Commands {}
abstract class SystemAdapter {}
abstract class GameSystem { SystemAdapter createAdapter(); }
class Query1<A> {}
class Query2<A, B> {}
class EventReader<T> {}
class EventWriter<T> {}
abstract class AppBuilder {}
abstract class Plugin {
  const Plugin();
  List<Type> get dependencies => const [];
  void build(AppBuilder app);
}
abstract class SceneDashBundle { void insertInto(World world, Entity entity); }
''';

/// Asserts the generated part for [source] satisfies [matcher].
Future<void> _expectGenerated(String source, Matcher matcher) {
  return testBuilder(
    sceneDashBuilder(BuilderOptions.empty),
    {_inputId: '$_imports$source', _stubId: _sceneDashStub},
    generateFor: {_inputId},
    outputs: {_outputId: decodedMatches(matcher)},
    onLog: (_) {},
  );
}

/// Asserts the generator rejects [source], reporting [fragment] in a log.
///
/// Under `testBuilder`, source_gen surfaces an `InvalidGenerationSource` as a
/// SEVERE log (no output) rather than a thrown exception.
Future<void> _expectRejected(String source, String fragment) async {
  final logs = <String>[];
  await testBuilder(
    sceneDashBuilder(BuilderOptions.empty),
    {_inputId: '$_imports$source', _stubId: _sceneDashStub},
    generateFor: {_inputId},
    onLog: (record) => logs.add('${record.message} ${record.error ?? ''}'),
  );
  expect(logs.join('\n'), contains(fragment));
}

void main() {
  group('positive generation', () {
    test('emits a system adapter and schedulable descriptor', () {
      return _expectGenerated(
        '''
@System()
final class FooSystem {
  const FooSystem();
  void run(Commands commands) {}
}
''',
        allOf(
          contains('class \$FooSystemAdapter implements SystemAdapter'),
          contains('_p0 = world.commands;'),
          contains('final fooSystem = SystemDescriptor('),
          contains('() => \$FooSystemAdapter(const FooSystem())'),
        ),
      );
    });

    test('emits access metadata (reads/writes) from query writes', () {
      return _expectGenerated(
        '''
@ObjectComponent()
final class Transform { double x = 0; }

@ObjectComponent()
final class Velocity { double x = 0; }

@Tag()
final class Player { const Player(); }

@System()
final class MoveSystem {
  const MoveSystem();
  void run(
    @Query(writes: [Transform], requires: [Player])
    Query2<Transform, Velocity> q,
  ) {}
}
''',
        allOf(
          contains('implements SystemAdapter, SystemAccessProvider'),
          contains('writes: <Type>{Transform}'),
          contains('reads: <Type>{Velocity}'),
        ),
      );
    });

    test('emits a bundle insertInto using the right stores', () {
      return _expectGenerated(
        '''
@ObjectComponent()
final class Pos { double x = 0; }

@Tag()
final class Marker { const Marker(); }

@Bundle()
final class FooBundle {
  final Pos pos;
  final Marker marker;
  const FooBundle(this.pos) : marker = const Marker();
}
''',
        allOf(
          contains('mixin _\$FooBundle implements SceneDashBundle'),
          contains(
            'world.ensureObjectStore<Pos>().insert(entity.index, self.pos)',
          ),
          contains('world.ensureTagStore<Marker>().add(entity.index)'),
        ),
      );
    });

    test('emits plugin dependencies from requires', () {
      return _expectGenerated(
        '''
@GamePlugin()
final class DepPlugin extends Plugin {
  const DepPlugin();
  @override
  void build(AppBuilder app) {}
}

@GamePlugin(requires: [DepPlugin])
final class MainPlugin extends Plugin {
  const MainPlugin();
  @override
  void build(AppBuilder app) {}
}
''',
        allOf(
          contains('base mixin _\$MainPlugin on Plugin'),
          contains('List<Type> get dependencies => const <Type>[DepPlugin]'),
          isNot(contains('mixin _\$DepPlugin')),
        ),
      );
    });
  });

  group('rejected input', () {
    test('packed components are recognized but rejected (object-first)', () {
      return _expectRejected('''
@PackedComponent()
final class Transform { final double x; const Transform(this.x); }
''', 'Packed components are not supported');
    });

    test('async systems are rejected', () {
      return _expectRejected('''
@System()
final class AsyncSystem {
  const AsyncSystem();
  Future<void> run() async {}
}
''', 'must return void');
    });

    test('unsupported run parameters are rejected', () {
      return _expectRejected('''
@System()
final class BadSystem {
  const BadSystem();
  void run(String bogus) {}
}
''', 'Unsupported parameter');
    });

    test('querying a tag as a component is rejected', () {
      return _expectRejected('''
@Tag()
final class Marker { const Marker(); }

@System()
final class TagQuerySystem {
  const TagQuerySystem();
  void run(@Query() Query1<Marker> q) {}
}
''', 'must be an @ObjectComponent');
    });
  });
}
