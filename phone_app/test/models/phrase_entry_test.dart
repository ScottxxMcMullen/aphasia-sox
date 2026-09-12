import 'package:flutter_test/flutter_test.dart';
import 'package:aphasia_app/models/phrase_entry.dart';

void main() {
  test('fromJson/toJson round-trip preserves all fields', () {
    final json = {
      'id': 'abc-123',
      'category': 'Greetings',
      'text': 'Hello.',
      'checksum': 'deadbeef',
    };

    final entry = PhraseEntry.fromJson(json);

    expect(entry.id, 'abc-123');
    expect(entry.category, 'Greetings');
    expect(entry.text, 'Hello.');
    expect(entry.checksum, 'deadbeef');
    expect(entry.toJson(), json);
  });

  test('equality compares all fields', () {
    const a = PhraseEntry(id: '1', category: 'Needs', text: 'Help.', checksum: 'x');
    const b = PhraseEntry(id: '1', category: 'Needs', text: 'Help.', checksum: 'x');
    const c = PhraseEntry(id: '2', category: 'Needs', text: 'Help.', checksum: 'x');

    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });
}
