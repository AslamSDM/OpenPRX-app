import 'package:flutter_test/flutter_test.dart';
import 'package:openprx_mobile/core/model_catalog.dart';
import 'package:openprx_mobile/rag/chunker.dart';

void main() {
  group('ModelCatalog', () {
    test('recommendedModel picks largest eligible model by RAM tier', () {
      final tinyRam = recommendedModel((1.5 * 1024).toInt());
      expect(tinyRam.id, 'lfm-2.5-230m-q4');

      final lowRam = recommendedModel((2.5 * 1024).toInt());
      expect(lowRam.id, 'llama-3.2-1b-q4');

      final mediumRam = recommendedModel(4 * 1024);
      expect(mediumRam.id, 'phi-3.5-mini-q4');

      final highRam = recommendedModel(6 * 1024);
      expect(highRam.id, 'gemma-3-4b-q4');

      final flagshipRam = recommendedModel(12 * 1024);
      expect(flagshipRam.id, 'gemma-3-4b-q4');
    });

    test('findModelById returns model or null', () {
      expect(findModelById('llama-3.2-3b-q4')?.name, 'Llama 3.2 3B Instruct');
      expect(findModelById('does-not-exist'), isNull);
    });

    test('all catalog URIs are hf:// prefixed', () {
      for (final m in kModelCatalog) {
        expect(m.hfUri, startsWith('hf://'));
      }
    });
  });

  group('Chunker', () {
    const chunker = Chunker(chunkSize: 100, overlap: 20);

    test('returns single chunk when text fits', () {
      expect(chunker.split('Short text'), equals(['Short text']));
    });

    test('splits with overlap', () {
      final text = 'a' * 250;
      final chunks = chunker.split(text);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(100));
      }
    });

    test('normalizes whitespace', () {
      final chunks = chunker.split('hello\n\n\tworld');
      expect(chunks.first, equals('hello world'));
    });
  });
}
