import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:aphasia_app/models/phrase_entry.dart';
import 'package:aphasia_app/services/library_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library_store_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('manifest returns empty list when nothing has been saved', () async {
    final store = LibraryStore(tempDir);
    expect(await store.manifest(), isEmpty);
  });

  test('saveEntry persists audio file and manifest entry', () async {
    final store = LibraryStore(tempDir);
    const entry = PhraseEntry(
      id: 'p1',
      category: 'Greetings',
      text: 'Hello.',
      checksum: 'abc',
    );

    await store.saveEntry(entry, Uint8List.fromList([1, 2, 3]));

    final manifest = await store.manifest();
    expect(manifest, [entry]);

    final audioFile = store.audioFileFor('p1');
    expect(audioFile, isNotNull);
    expect(await audioFile!.readAsBytes(), [1, 2, 3]);
  });

  test('saveEntry with an existing id replaces the old entry', () async {
    final store = LibraryStore(tempDir);
    const original = PhraseEntry(id: 'p1', category: 'A', text: 'Old', checksum: 'x');
    const updated = PhraseEntry(id: 'p1', category: 'A', text: 'New', checksum: 'y');

    await store.saveEntry(original, Uint8List.fromList([1]));
    await store.saveEntry(updated, Uint8List.fromList([2]));

    final manifest = await store.manifest();
    expect(manifest, [updated]);
    expect(await store.audioFileFor('p1')!.readAsBytes(), [2]);
  });

  test('audioFileFor returns null for an unknown id', () async {
    final store = LibraryStore(tempDir);
    expect(store.audioFileFor('does-not-exist'), isNull);
  });

  test('manifest persists across store instances pointed at the same directory', () async {
    final store = LibraryStore(tempDir);
    const entry = PhraseEntry(id: 'p1', category: 'Needs', text: 'Help.', checksum: 'x');
    await store.saveEntry(entry, Uint8List.fromList([9]));

    final reloaded = LibraryStore(tempDir);
    expect(await reloaded.manifest(), [entry]);
  });

  test('deleteEntry removes both the manifest entry and its audio file', () async {
    final store = LibraryStore(tempDir);
    const entry = PhraseEntry(id: 'p1', category: 'Needs', text: 'Help.', checksum: 'x');
    await store.saveEntry(entry, Uint8List.fromList([1]));

    await store.deleteEntry('p1');

    expect(await store.manifest(), isEmpty);
    expect(store.audioFileFor('p1'), isNull);
  });

  test('deleteEntry is a no-op for an unknown id', () async {
    final store = LibraryStore(tempDir);
    await store.deleteEntry('does-not-exist');
    expect(await store.manifest(), isEmpty);
  });

  test('deletedIds returns an empty set when nothing has been deleted', () async {
    final store = LibraryStore(tempDir);
    expect(await store.deletedIds(), isEmpty);
  });

  test('markDeleted removes the entry and records a tombstone', () async {
    final store = LibraryStore(tempDir);
    const entry = PhraseEntry(id: 'p1', category: 'Needs', text: 'Help.', checksum: 'x');
    await store.saveEntry(entry, Uint8List.fromList([1]));

    await store.markDeleted('p1');

    expect(await store.manifest(), isEmpty);
    expect(store.audioFileFor('p1'), isNull);
    expect(await store.deletedIds(), {'p1'});
  });

  test('markDeleted tombstone persists across store instances', () async {
    final store = LibraryStore(tempDir);
    const entry = PhraseEntry(id: 'p1', category: 'Needs', text: 'Help.', checksum: 'x');
    await store.saveEntry(entry, Uint8List.fromList([1]));
    await store.markDeleted('p1');

    final reloaded = LibraryStore(tempDir);
    expect(await reloaded.deletedIds(), {'p1'});
    expect(await reloaded.manifest(), isEmpty);
  });

  test('moveEntry changes the category and leaves everything else alone', () async {
    final store = LibraryStore(tempDir);
    const entry = PhraseEntry(id: 'p1', category: 'Greetings', text: 'Hello.', checksum: 'abc');
    await store.saveEntry(entry, Uint8List.fromList([1, 2, 3]));

    await store.moveEntry('p1', 'Church');

    final manifest = await store.manifest();
    expect(manifest, [
      const PhraseEntry(id: 'p1', category: 'Church', text: 'Hello.', checksum: 'abc'),
    ]);
    // The audio is what makes a phrase usable offline — a move must never
    // disturb it.
    expect(await store.audioFileFor('p1')!.readAsBytes(), [1, 2, 3]);
  });

  test('moveEntry keeps the manifest in its existing order', () async {
    final store = LibraryStore(tempDir);
    await store.saveEntry(
      const PhraseEntry(id: 'p1', category: 'A', text: 'First', checksum: 'x'),
      Uint8List.fromList([1]),
    );
    await store.saveEntry(
      const PhraseEntry(id: 'p2', category: 'A', text: 'Second', checksum: 'y'),
      Uint8List.fromList([2]),
    );
    await store.saveEntry(
      const PhraseEntry(id: 'p3', category: 'A', text: 'Third', checksum: 'z'),
      Uint8List.fromList([3]),
    );

    await store.moveEntry('p2', 'B');

    final manifest = await store.manifest();
    expect(manifest.map((e) => e.id), ['p1', 'p2', 'p3']);
    expect(manifest[1].category, 'B');
  });

  test('moveEntry is a no-op for an unknown id', () async {
    final store = LibraryStore(tempDir);
    const entry = PhraseEntry(id: 'p1', category: 'A', text: 'Hello.', checksum: 'x');
    await store.saveEntry(entry, Uint8List.fromList([1]));

    await store.moveEntry('does-not-exist', 'B');

    expect(await store.manifest(), [entry]);
  });

  test('moveEntry persists across store instances', () async {
    final store = LibraryStore(tempDir);
    await store.saveEntry(
      const PhraseEntry(id: 'p1', category: 'Greetings', text: 'Hello.', checksum: 'x'),
      Uint8List.fromList([1]),
    );
    await store.moveEntry('p1', 'Church');

    final reloaded = LibraryStore(tempDir);
    expect((await reloaded.manifest()).single.category, 'Church');
  });

  test('manifest returns empty list when manifest file contains invalid JSON', () async {
    final store = LibraryStore(tempDir);

    // Manually create a corrupt manifest file
    final manifestFile = File('${tempDir.path}/manifest.json');
    await manifestFile.create(recursive: true);
    await manifestFile.writeAsString('{ invalid json }');

    // manifest() should gracefully return [] instead of throwing
    final result = await store.manifest();
    expect(result, isEmpty);
  });

  test('saveEntry round-trip works correctly with atomic writes', () async {
    final store = LibraryStore(tempDir);
    const entry1 = PhraseEntry(id: 'p1', category: 'Greetings', text: 'Hello.', checksum: 'abc');
    const entry2 = PhraseEntry(id: 'p2', category: 'Needs', text: 'Help.', checksum: 'def');

    // Save first entry
    await store.saveEntry(entry1, Uint8List.fromList([1, 2, 3]));

    // Verify it was saved
    var manifest = await store.manifest();
    expect(manifest, [entry1]);

    // Save second entry
    await store.saveEntry(entry2, Uint8List.fromList([4, 5, 6]));

    // Verify both are in manifest and audio files exist
    manifest = await store.manifest();
    expect(manifest, [entry1, entry2]);
    expect(await store.audioFileFor('p1')!.readAsBytes(), [1, 2, 3]);
    expect(await store.audioFileFor('p2')!.readAsBytes(), [4, 5, 6]);
  });
}
