import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene_object.dart';

SceneObject _object(String type) {
  return SceneObject(id: 'o1', type: type, x: 0, y: 0, width: 80, height: 40);
}

void main() {
  test('register, get, and list', () {
    final registry = ObjectRegistry();
    final type = ObjectType(
      typeId: 'box',
      displayName: 'Box',
      defaultProps: const {'fill': '#000000'},
      builder: (context, object, ctx) => const SizedBox(),
    );

    registry.register(type);

    expect(registry.get('box'), same(type));
    expect(registry.list(), [type]);
    expect(registry.get('missing'), isNull);
  });

  test('duplicate typeId throws', () {
    final registry = ObjectRegistry();
    final type = ObjectType(
      typeId: 'box',
      displayName: 'Box',
      defaultProps: const {},
      builder: (context, object, ctx) => const SizedBox(),
    );
    registry.register(type);

    expect(() => registry.register(type), throwsStateError);
  });

  testWidgets('build for a known type returns that widget', (tester) async {
    final registry = ObjectRegistry();
    registry.register(
      ObjectType(
        typeId: 'hello',
        displayName: 'Hello',
        defaultProps: const {},
        builder: (context, object, ctx) => const Text('hello-built'),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => registry.build(context, _object('hello')),
        ),
      ),
    );

    expect(find.text('hello-built'), findsOneWidget);
  });

  testWidgets('unknown type yields a placeholder and does not throw', (
    tester,
  ) async {
    final registry = ObjectRegistry();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => registry.build(context, _object('not.a.type')),
        ),
      ),
    );

    expect(find.byType(UnknownObjectPlaceholder), findsOneWidget);
    expect(find.text('not.a.type'), findsOneWidget);
  });

  testWidgets('builder exceptions become a placeholder', (tester) async {
    final registry = ObjectRegistry();
    registry.register(
      ObjectType(
        typeId: 'boom',
        displayName: 'Boom',
        defaultProps: const {},
        builder: (context, object, ctx) => throw StateError('nope'),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => registry.build(context, _object('boom')),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(UnknownObjectPlaceholder), findsOneWidget);
  });

  test('createBuiltinRegistry lists built-in typeIds', () {
    final ids = createBuiltinRegistry().list().map((t) => t.typeId).toList();
    expect(ids, ['box', 'text', 'button', 'debug.rect']);
  });

  testWidgets('builtin box, text, and button build distinct widgets', (
    tester,
  ) async {
    final registry = createBuiltinRegistry();
    final box = _object('box').copyWith(
      props: const {'fill': '#7AA3C7', 'cornerRadius': 8, 'opacity': 1},
    );
    final text = _object('text').copyWith(
      props: const {
        'content': 'hello-text',
        'fontSize': 18,
        'color': '#1B1B1B',
      },
    );
    final button = _object('button')
        .copyWith(props: const {'label': 'hello-button'});

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            SizedBox(width: 80, height: 40, child: _Build(registry, box)),
            SizedBox(width: 80, height: 40, child: _Build(registry, text)),
            SizedBox(width: 80, height: 40, child: _Build(registry, button)),
          ],
        ),
      ),
    );

    expect(find.text('hello-text'), findsOneWidget);
    expect(find.text('hello-button'), findsOneWidget);
    expect(find.byType(UnknownObjectPlaceholder), findsNothing);
    expect(find.byType(DecoratedBox), findsWidgets);
  });
}

class _Build extends StatelessWidget {
  const _Build(this.registry, this.object);

  final ObjectRegistry registry;
  final SceneObject object;

  @override
  Widget build(BuildContext context) => registry.build(context, object);
}
