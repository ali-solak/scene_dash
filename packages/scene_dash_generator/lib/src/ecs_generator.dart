import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart' show BuildStep;
import 'package:scene_dash/scene_dash.dart';
import 'package:source_gen/source_gen.dart';

import 'component_kind.dart';

const _systemChecker = TypeChecker.typeNamed(System, inPackage: 'scene_dash');
const _bundleChecker = TypeChecker.typeNamed(Bundle, inPackage: 'scene_dash');
const _packedChecker = TypeChecker.typeNamed(
  PackedComponent,
  inPackage: 'scene_dash',
);
const _queryChecker = TypeChecker.typeNamed(Query, inPackage: 'scene_dash');
const _resourceChecker = TypeChecker.typeNamed(
  Resource,
  inPackage: 'scene_dash',
);
const _gamePluginChecker = TypeChecker.typeNamed(
  GamePlugin,
  inPackage: 'scene_dash',
);

const _queryTypeNames = {'Query1', 'Query2', 'Query3', 'Query4'};
const _singleTypeNames = {'Single', 'OptionalSingle'};

/// Aggregating generator for the scene_dash annotations.
///
/// Validates components and generates a `SystemAdapter` + `mixin _$YourSystem`
/// for every `@System`, a `mixin _$YourBundle` for every `@Bundle`, and plugin
/// dependency metadata for `@GamePlugin`.
///
/// The architecture is object-first: `@ObjectComponent` and `@Tag` are the
/// supported component models. `@PackedComponent` is recognized-but-rejected —
/// packed typed-array storage is an optional, benchmark-gated future phase (see
/// `docs/concept.md`), not part of the active roadmap.
class EcsGenerator extends Generator {
  const EcsGenerator();

  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    final buffer = StringBuffer();

    // Reject packed components: object components are the default model and
    // packed typed-array storage is an optional future phase, not implemented.
    for (final element in library.classes) {
      if (_packedChecker.hasAnnotationOf(element, throwOnUnresolved: false)) {
        throw InvalidGenerationSource(
          'Packed components are not supported: object components are the '
          'default storage model. Use @ObjectComponent. Packed typed-array '
          'storage is an optional future phase (see docs/concept.md).',
          element: element,
        );
      }
    }

    final libraryUri = buildStep.inputId.uri.toString();

    // Systems may be `@System` classes or top-level `@System` functions.
    for (final annotated in library.annotatedWith(_systemChecker)) {
      final element = annotated.element;
      if (element is ClassElement) {
        buffer.writeln(_generateClassSystem(element, libraryUri));
      } else if (element is ExecutableElement) {
        buffer.writeln(_generateFunctionSystem(element, libraryUri));
      } else {
        throw InvalidGenerationSource(
          '@System must annotate a class or a top-level function.',
          element: element,
        );
      }
    }

    for (final element in library.classes) {
      if (_bundleChecker.hasAnnotationOf(element, throwOnUnresolved: false)) {
        buffer.writeln(_generateBundle(element));
      }
      final pluginAnno = _gamePluginChecker.firstAnnotationOf(
        element,
        throwOnUnresolved: false,
      );
      if (pluginAnno != null) {
        final plugin = _generatePlugin(element, ConstantReader(pluginAnno));
        if (plugin != null) buffer.writeln(plugin);
      }
    }

    return buffer.toString();
  }
}

// --- System generation ---

/// The injected-parameter wiring shared by class and function systems.
typedef _SystemWiring = ({
  String fieldBlock,
  String ensureBlock,
  String initBlock,
  String argList,
  String readsList,
  String writesList,
});

/// Validates that an `@System`'s `run` is synchronous (returns void).
void _checkSyncRun(ExecutableElement run, String name, Element errorElement) {
  if (run.returnType is! VoidType && !run.returnType.isDartCoreNull) {
    final rt = run.returnType.getDisplayString();
    if (rt != 'void') {
      throw InvalidGenerationSource(
        '@System $name must return void (got $rt). Systems must be synchronous.',
        element: errorElement,
      );
    }
  }
}

/// Builds the adapter field declarations, store-ensures, init statements,
/// argument list and access metadata from a system's `run` parameters. Shared by
/// `@System` classes (where `run` is the `run` method) and top-level `@System`
/// functions (where `run` is the function itself).
_SystemWiring _wireRunParams(
  ExecutableElement run,
  String name,
  Element errorElement,
) {
  final fields = <String>[];
  final ensures = <String>{};
  final inits = <String>[];
  final args = <String>[];
  final reads = <String>{};
  final writes = <String>{};

  var index = 0;
  for (final param in run.formalParameters) {
    final field = '_p$index';
    final type = param.type;
    final typeStr = type.getDisplayString();
    final interfaceName = type is InterfaceType ? type.element.name : null;

    if (interfaceName != null && _queryTypeNames.contains(interfaceName)) {
      _emitQueryParam(
        param: param,
        type: type as InterfaceType,
        field: field,
        fields: fields,
        ensures: ensures,
        inits: inits,
        reads: reads,
        writes: writes,
      );
    } else if (interfaceName != null &&
        _singleTypeNames.contains(interfaceName)) {
      _emitSingleParam(
        param: param,
        type: type as InterfaceType,
        wrapper: interfaceName,
        field: field,
        fields: fields,
        ensures: ensures,
        inits: inits,
        reads: reads,
        writes: writes,
      );
    } else if (_resourceChecker.hasAnnotationOf(param,
        throwOnUnresolved: false)) {
      fields.add('late final $typeStr $field;');
      inits.add('$field = world.resources.get<$typeStr>();');
    } else if (interfaceName == 'Commands') {
      fields.add('late final Commands $field;');
      inits.add('$field = world.commands;');
    } else if (interfaceName == 'EventReader' ||
        interfaceName == 'EventWriter') {
      final eventType =
          (type as InterfaceType).typeArguments.first.getDisplayString();
      final factory = interfaceName == 'EventReader' ? 'reader' : 'writer';
      fields.add('late final $typeStr $field;');
      inits.add('world.registerEvent<$eventType>();');
      inits.add('$field = world.eventChannel<$eventType>().$factory();');
    } else {
      throw InvalidGenerationSource(
        'Unsupported parameter `${param.name} : $typeStr` in $name. '
        'Expected a Query1..Query4, Single/OptionalSingle, an @Resource(), '
        'Commands, EventReader or EventWriter.',
        element: errorElement,
      );
    }

    args.add(field);
    index++;
  }

  // Reads are queried components that are not declared as writes.
  reads.removeAll(writes);

  return (
    fieldBlock: fields.map((f) => '  $f').join('\n'),
    ensureBlock: ensures.map((e) => '    $e').join('\n'),
    initBlock: inits.map((i) => '    $i').join('\n'),
    argList: args.join(', '),
    readsList: reads.join(', '),
    writesList: writes.join(', '),
  );
}

/// Lower-cases the first character.
String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// Upper-cases the first character.
String _upperFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// The generated top-level descriptor name for a system, e.g.
/// `MovePlayerSystem` -> `movePlayerSystem`, `evaluateGameRules` ->
/// `evaluateGameRulesSystem`.
String _descriptorName(String name) {
  final lower = _lowerFirst(name);
  return lower.endsWith('System') ? lower : '${lower}System';
}

/// Generates the adapter + descriptor for an `@System` class. The adapter wraps
/// a `const` instance of the system and calls its `run`.
String _generateClassSystem(ClassElement system, String libraryUri) {
  final name = system.name;
  if (name == null) {
    throw InvalidGenerationSource('@System class has no name.');
  }
  final run = system.getMethod('run');
  if (run == null) {
    throw InvalidGenerationSource(
      '@System $name must declare a synchronous `run(...)` method.',
      element: system,
    );
  }
  _checkSyncRun(run, '$name.run', system);

  final w = _wireRunParams(run, '$name.run', system);
  final adapter = '\$${name}Adapter';
  final descriptor = _descriptorName(name);

  return '''
class $adapter implements SystemAdapter, SystemAccessProvider {
  $adapter(this._system);

  final $name _system;
${w.fieldBlock}

  @override
  void initialize(World world) {
${w.ensureBlock}
${w.initBlock}
  }

  @override
  SystemAccess get access => const SystemAccess(
        reads: <Type>{${w.readsList}},
        writes: <Type>{${w.writesList}},
      );

  @override
  void run() {
    _system.run(${w.argList});
  }
}

/// Schedulable descriptor for [$name]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final $descriptor = SystemDescriptor(
  const SystemRef('$libraryUri', '$name'),
  () => $adapter(const $name()),
);
''';
}

/// Generates the adapter + descriptor for a top-level `@System` function. The
/// adapter injects parameters and calls the function directly — no class, no
/// mixin, no constructor ceremony.
String _generateFunctionSystem(ExecutableElement fn, String libraryUri) {
  final name = fn.name;
  if (name == null || name.isEmpty) {
    throw InvalidGenerationSource('@System function has no name.');
  }
  _checkSyncRun(fn, '$name(...)', fn);

  final w = _wireRunParams(fn, '$name(...)', fn);
  final adapter = '\$${_upperFirst(name)}Adapter';
  final descriptor = _descriptorName(name);

  return '''
class $adapter implements SystemAdapter, SystemAccessProvider {
${w.fieldBlock}

  @override
  void initialize(World world) {
${w.ensureBlock}
${w.initBlock}
  }

  @override
  SystemAccess get access => const SystemAccess(
        reads: <Type>{${w.readsList}},
        writes: <Type>{${w.writesList}},
      );

  @override
  void run() {
    $name(${w.argList});
  }
}

/// Schedulable descriptor for [$name]. Pass to `app.addSystem` and reference in
/// `after`/`before`.
final $descriptor = SystemDescriptor(
  const SystemRef('$libraryUri', '$name'),
  () => $adapter(),
);
''';
}

void _emitQueryParam({
  required FormalParameterElement param,
  required InterfaceType type,
  required String field,
  required List<String> fields,
  required Set<String> ensures,
  required List<String> inits,
  required Set<String> reads,
  required Set<String> writes,
}) {
  final queryType = type.getDisplayString();
  final components = type.typeArguments;

  final queryAnno = _queryChecker.firstAnnotationOf(
    param,
    throwOnUnresolved: false,
  );
  final reader = queryAnno == null ? null : ConstantReader(queryAnno);
  final requires = _typeList(reader, 'requires');
  final excludes = _typeList(reader, 'excludes');
  final writeTypes =
      _typeList(reader, 'writes').map((t) => t.getDisplayString()).toSet();

  for (final component in components) {
    ensures.add(ensureStoreCall(component, forQuery: true));
    // Access metadata: queried components are reads unless declared writes.
    final name = component.getDisplayString();
    if (writeTypes.contains(name)) {
      writes.add(name);
    } else {
      reads.add(name);
    }
  }
  for (final filter in [...requires, ...excludes]) {
    ensures.add(ensureStoreCall(filter, forQuery: false));
  }

  final arity = components.length;
  final typeArgs = components.map((t) => t.getDisplayString()).join(', ');
  final withList = requires.map((t) => t.getDisplayString()).join(', ');
  final withoutList = excludes.map((t) => t.getDisplayString()).join(', ');

  fields.add('late final $queryType $field;');
  inits.add(
    '$field = world.query$arity<$typeArgs>('
    'withTypes: const <Type>[$withList], '
    'withoutTypes: const <Type>[$withoutList]);',
  );
}

/// Emits a `Single<A>` / `OptionalSingle<A>` parameter: a one-component query
/// (with the same `@Query` filters) wrapped so the system resolves the single
/// matching entity. [wrapper] is `Single` or `OptionalSingle`.
void _emitSingleParam({
  required FormalParameterElement param,
  required InterfaceType type,
  required String wrapper,
  required String field,
  required List<String> fields,
  required Set<String> ensures,
  required List<String> inits,
  required Set<String> reads,
  required Set<String> writes,
}) {
  final wrapperType = type.getDisplayString();
  final component = type.typeArguments.first;
  final componentStr = component.getDisplayString();

  final queryAnno = _queryChecker.firstAnnotationOf(
    param,
    throwOnUnresolved: false,
  );
  final reader = queryAnno == null ? null : ConstantReader(queryAnno);
  final requires = _typeList(reader, 'requires');
  final excludes = _typeList(reader, 'excludes');
  final writeTypes =
      _typeList(reader, 'writes').map((t) => t.getDisplayString()).toSet();

  ensures.add(ensureStoreCall(component, forQuery: true));
  if (writeTypes.contains(componentStr)) {
    writes.add(componentStr);
  } else {
    reads.add(componentStr);
  }
  for (final filter in [...requires, ...excludes]) {
    ensures.add(ensureStoreCall(filter, forQuery: false));
  }

  final withList = requires.map((t) => t.getDisplayString()).join(', ');
  final withoutList = excludes.map((t) => t.getDisplayString()).join(', ');

  fields.add('late final $wrapperType $field;');
  inits.add(
    '$field = $wrapper<$componentStr>(world.query1<$componentStr>('
    'withTypes: const <Type>[$withList], '
    'withoutTypes: const <Type>[$withoutList]));',
  );
}

List<DartType> _typeList(ConstantReader? reader, String field) {
  if (reader == null) return const <DartType>[];
  final value = reader.read(field);
  if (value.isNull) return const <DartType>[];
  return [
    for (final entry in value.listValue) ?entry.toTypeValue(),
  ];
}

// --- Bundle generation ---

String _generateBundle(ClassElement bundle) {
  final name = bundle.name;
  if (name == null) {
    throw InvalidGenerationSource('@Bundle class has no name.');
  }

  final statements = <String>[];
  for (final fieldElement in bundle.fields) {
    if (fieldElement.isStatic) continue;
    final fieldName = fieldElement.name;
    if (fieldName == null) continue;
    final type = fieldElement.type;
    final typeStr = type.getDisplayString();

    switch (componentKindOf(type)) {
      case ComponentKind.object:
        statements.add(
          'world.ensureObjectStore<$typeStr>().insert(entity.index, '
          'self.$fieldName);',
        );
      case ComponentKind.tag:
        statements.add(
          'world.ensureTagStore<$typeStr>().add(entity.index);',
        );
      case ComponentKind.packed:
        throw InvalidGenerationSource(
          'Bundle $name has packed component field `$fieldName` ($typeStr). '
          'Packed components are not supported; use @ObjectComponent. Packed '
          'typed-array storage is an optional future phase (docs/concept.md).',
          element: bundle,
        );
      case ComponentKind.unknown:
        throw InvalidGenerationSource(
          'Bundle $name field `$fieldName` has type $typeStr, which is not a '
          'component (@ObjectComponent / @Tag / @PackedComponent).',
          element: bundle,
        );
    }
  }

  final body = statements.map((s) => '    $s').join('\n');

  return '''
mixin _\$$name implements SceneDashBundle {
  @override
  void insertInto(World world, Entity entity) {
    final self = this as $name;
$body
  }
}
''';
}

// --- Plugin generation ---

/// Emits a `base mixin _$YourPlugin on Plugin` that overrides [Plugin.dependencies]
/// from `@GamePlugin(requires: [...])`. Returns `null` when there are no
/// requirements (no mixin needed — apply it only when you declare `requires`).
String? _generatePlugin(ClassElement plugin, ConstantReader annotation) {
  final name = plugin.name;
  if (name == null) {
    throw InvalidGenerationSource('@GamePlugin class has no name.');
  }

  final requires = _typeList(annotation, 'requires');
  if (requires.isEmpty) return null;

  final deps = requires.map((t) => t.getDisplayString()).join(', ');

  return '''
base mixin _\$$name on Plugin {
  @override
  List<Type> get dependencies => const <Type>[$deps];
}
''';
}
