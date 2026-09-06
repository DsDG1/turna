import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/utils/validated_file_picker.dart';

void main() {
  group('ValidatedFilePicker suffix normalization and matching', () {
    test('normalizes extensions to lowercase with leading dot', () {
      final suffixes = ValidatedFilePicker.normalizedSuffixes(['apkg', '.COLPKG', 'MD']);
      expect(suffixes, equals({'.apkg', '.colpkg', '.md'}));
    });

    test('hasAllowedSuffix matches case-insensitively', () {
      final suffixes = {'.apkg', '.colpkg'};
      expect(ValidatedFilePicker.hasAllowedSuffix('/storage/vocab.apkg', suffixes), isTrue);
      expect(ValidatedFilePicker.hasAllowedSuffix('/storage/vocab.APKG', suffixes), isTrue);
      expect(ValidatedFilePicker.hasAllowedSuffix('/storage/vocab.colpkg', suffixes), isTrue);
      expect(ValidatedFilePicker.hasAllowedSuffix('/storage/vocab.apkg ', suffixes), isTrue);
      expect(ValidatedFilePicker.hasAllowedSuffix('/storage/vocab.txt', suffixes), isFalse);
    });

    test('findMatchingSuffix identifies correct suffix', () {
      final suffixes = {'.apkg', '.colpkg'};
      expect(ValidatedFilePicker.findMatchingSuffix('deck.apkg', suffixes), equals('.apkg'));
      expect(ValidatedFilePicker.findMatchingSuffix('deck.COLPKG', suffixes), equals('.colpkg'));
      expect(ValidatedFilePicker.findMatchingSuffix('deck.txt', suffixes), isNull);
    });

    test('findWrappedSuffix identifies WeChat and browser wrapped extensions', () {
      final suffixes = {'.apkg', '.colpkg'};
      // WeChat download (.1, .2)
      expect(ValidatedFilePicker.findWrappedSuffix('deck.apkg.1', suffixes), equals('.apkg'));
      expect(ValidatedFilePicker.findWrappedSuffix('collection.colpkg.1', suffixes), equals('.colpkg'));
      // Browser download (.bin, .zip, .download)
      expect(ValidatedFilePicker.findWrappedSuffix('deck.apkg.bin', suffixes), equals('.apkg'));
      expect(ValidatedFilePicker.findWrappedSuffix('deck.apkg.zip', suffixes), equals('.apkg'));
      expect(ValidatedFilePicker.findWrappedSuffix('deck.apkg.download', suffixes), equals('.apkg'));
      // Download counter
      expect(ValidatedFilePicker.findWrappedSuffix('deck.apkg(1)', suffixes), equals('.apkg'));
      expect(ValidatedFilePicker.findWrappedSuffix('deck.apkg_1', suffixes), equals('.apkg'));
      // Direct extension
      expect(ValidatedFilePicker.findWrappedSuffix('deck.apkg', suffixes), equals('.apkg'));
      // Unrelated extensions should not match
      expect(ValidatedFilePicker.findWrappedSuffix('photo.jpg', suffixes), isNull);
      expect(ValidatedFilePicker.findWrappedSuffix('notes.txt', suffixes), isNull);
    });
  });

  group('ValidatedFilePicker.resolvePickedFilePath', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('picker_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('returns direct path when rawPath has allowed suffix', () async {
      final file = File('${tempDir.path}/deck.apkg')..writeAsStringSync('dummy');
      final platformFile = PlatformFile(
        name: 'deck.apkg',
        size: 5,
        path: file.path,
      );

      final resolved = await ValidatedFilePicker.resolvePickedFilePath(
        platformFile,
        {'.apkg', '.colpkg'},
      );

      expect(resolved, equals(file.path));
    });

    test('stages file when path has no extension but name has allowed suffix', () async {
      // Common Android SAF behavior: cached as hash/number
      final file = File('${tempDir.path}/1725638491')..writeAsStringSync('content');
      final platformFile = PlatformFile(
        name: 'my_deck.apkg',
        size: 7,
        path: file.path,
      );

      final resolved = await ValidatedFilePicker.resolvePickedFilePath(
        platformFile,
        {'.apkg'},
      );

      expect(resolved, isNotNull);
      expect(resolved!.endsWith('my_deck.apkg'), isTrue);
      expect(File(resolved).existsSync(), isTrue);
      expect(File(resolved).readAsStringSync(), equals('content'));
    });

    test('stages WeChat .apkg.1 file to clean .apkg path', () async {
      final file = File('${tempDir.path}/turkish.apkg.1')..writeAsStringSync('wechat_deck');
      final platformFile = PlatformFile(
        name: 'turkish.apkg.1',
        size: 11,
        path: file.path,
      );

      final resolved = await ValidatedFilePicker.resolvePickedFilePath(
        platformFile,
        {'.apkg'},
      );

      expect(resolved, isNotNull);
      expect(resolved!.endsWith('turkish.apkg'), isTrue);
      expect(File(resolved).existsSync(), isTrue);
      expect(File(resolved).readAsStringSync(), equals('wechat_deck'));
    });

    test('stages browser .apkg.bin file to clean .apkg path', () async {
      final file = File('${tempDir.path}/download.apkg.bin')..writeAsStringSync('browser_deck');
      final platformFile = PlatformFile(
        name: 'download.apkg.bin',
        size: 12,
        path: file.path,
      );

      final resolved = await ValidatedFilePicker.resolvePickedFilePath(
        platformFile,
        {'.apkg'},
      );

      expect(resolved, isNotNull);
      expect(resolved!.endsWith('download.apkg'), isTrue);
      expect(File(resolved).existsSync(), isTrue);
      expect(File(resolved).readAsStringSync(), equals('browser_deck'));
    });

    test('detects real Anki package even when named .bin or .zip', () async {
      // Find a real fixture package
      final fixture = File('test/fixtures/anki_official/packages/01-basic-unicode.apkg');
      if (!fixture.existsSync()) return;

      // Copy to .bin extension
      final disguised = File('${tempDir.path}/deck.bin');
      fixture.copySync(disguised.path);

      final platformFile = PlatformFile(
        name: 'deck.bin',
        size: disguised.lengthSync(),
        path: disguised.path,
      );

      final resolved = await ValidatedFilePicker.resolvePickedFilePath(
        platformFile,
        {'.apkg'},
      );

      expect(resolved, isNotNull);
      expect(resolved!.endsWith('.apkg'), isTrue);
      expect(File(resolved).existsSync(), isTrue);
    });

    test('returns null for non-matching file', () async {
      final file = File('${tempDir.path}/image.png')..writeAsStringSync('not_anki');
      final platformFile = PlatformFile(
        name: 'image.png',
        size: 8,
        path: file.path,
      );

      final resolved = await ValidatedFilePicker.resolvePickedFilePath(
        platformFile,
        {'.apkg', '.colpkg'},
      );

      expect(resolved, isNull);
    });
  });
}
