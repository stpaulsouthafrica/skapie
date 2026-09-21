import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/command_palette.dart';

void main() {
  const actions = [
    CommandAction(id: 'add-llm', label: 'Add LLM'),
    CommandAction(id: 'add-system-prompt', label: 'Add System Prompt'),
    CommandAction(id: 'settings', label: 'Settings'),
  ];

  test('empty query keeps every action', () {
    expect(filterCommandActions(actions, ''), actions);
    expect(filterCommandActions(actions, '  '), actions);
  });

  test('substring filter is case insensitive on the label', () {
    expect(
      filterCommandActions(actions, 'llm').map((action) => action.id),
      ['add-llm'],
    );
    expect(
      filterCommandActions(actions, 'SET').map((action) => action.id),
      ['settings'],
    );
  });

  test('fuzzy subsequence still matches a label', () {
    expect(
      filterCommandActions(actions, 'asp').map((action) => action.id),
      ['add-system-prompt'],
    );
  });
}
