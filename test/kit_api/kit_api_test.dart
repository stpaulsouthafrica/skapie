import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  late SceneStore store;
  late ObjectRegistry registry;
  late KitApi api;

  setUp(() {
    store = SceneStore();
    registry = createBuiltinRegistry();
    api = KitApi(store: store, registry: registry);
  });

  test('addObject uses registry defaults and appears in the store', () {
    final id = api.addObject(typeId: 'box', x: 10, y: 20);

    expect(store.document.objects, hasLength(1));
    final object = store.document.objects.single;
    expect(object.id, id);
    expect(object.type, 'box');
    expect(object.x, 10);
    expect(object.y, 20);
    expect(object.width, 160);
    expect(object.height, 100);
    expect(object.props['fill'], '#7AA3C7');
    expect(object.props['cornerRadius'], 8);
  });

  test('unknown typeId throws and leaves the scene unchanged', () {
    expect(
      () => api.addObject(typeId: 'not.a.type'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('not.a.type'),
        ),
      ),
    );
    expect(store.document.objects, isEmpty);
  });

  test('updateProps, updateFrame, setLocked, removeObject; undo via store', () {
    final id = api.addObject(typeId: 'text', props: const {'content': 'old'});

    api.updateFrame(id: id, x: 5, y: 6);
    api.updateProps(id, const {'content': 'new'});
    api.setLocked(id, true);

    var object = store.document.objectById(id)!;
    expect(object.x, 5);
    expect(object.y, 6);
    expect(object.props['content'], 'new');
    expect(object.locked, isTrue);

    store.undo();
    expect(store.document.objectById(id)!.locked, isFalse);
    store.undo();
    expect(store.document.objectById(id)!.props['content'], 'old');
    store.undo();
    expect(store.document.objectById(id)!.x, 0);

    api.removeObject(id);
    expect(store.document.objects, isEmpty);
    store.undo();
    expect(store.document.objects, hasLength(1));
  });

  test('registerKit duplicate id throws', () {
    const recipe = KitRecipe(
      id: 'demo.dup',
      displayName: 'Dup',
      objects: [KitObjectSpec(typeId: 'box', x: 0, y: 0)],
    );
    api.registerKit(recipe);
    expect(() => api.registerKit(recipe), throwsStateError);
  });

  test('instantiate places relative coords at origin', () {
    api.registerKit(
      const KitRecipe(
        id: 'demo.pair',
        displayName: 'Pair',
        objects: [
          KitObjectSpec(typeId: 'box', x: 0, y: 0, width: 40, height: 20),
          KitObjectSpec(
            typeId: 'text',
            x: 4,
            y: 2,
            width: 30,
            height: 10,
            props: {'content': 'hi'},
          ),
        ],
      ),
    );

    final ids = api.instantiate('demo.pair', origin: const Offset(100, 50));
    expect(ids, hasLength(2));
    expect(store.document.objects.map((o) => o.type), ['box', 'text']);
    expect(store.document.objects[0].x, 100);
    expect(store.document.objects[0].y, 50);
    expect(store.document.objects[1].x, 104);
    expect(store.document.objects[1].y, 52);
    expect(store.document.objects[1].props['content'], 'hi');
  });

  test('instantiate with unknown spec type fails before any apply', () {
    api.registerKit(
      const KitRecipe(
        id: 'demo.bad',
        displayName: 'Bad',
        objects: [
          KitObjectSpec(typeId: 'box', x: 0, y: 0),
          KitObjectSpec(typeId: 'nope.kit', x: 1, y: 1),
        ],
      ),
    );

    expect(
      () => api.instantiate('demo.bad', origin: Offset.zero),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('nope.kit'),
        ),
      ),
    );
    expect(store.document.objects, isEmpty);
  });
}
