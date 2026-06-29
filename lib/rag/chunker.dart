/// Naive fixed-size text chunker used for RAG ingestion.
class Chunker {
  final int chunkSize;
  final int overlap;

  const Chunker({this.chunkSize = 4000, this.overlap = 400});

  List<String> split(String text) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= chunkSize) return [cleaned];
    final chunks = <String>[];
    var start = 0;
    while (start < cleaned.length) {
      final end = (start + chunkSize).clamp(0, cleaned.length);
      chunks.add(cleaned.substring(start, end));
      if (end == cleaned.length) break;
      final nextStart = start + chunkSize - overlap;
      if (nextStart <= start) break; // overlap >= chunkSize would loop
      start = nextStart;
    }
    return chunks.where((c) => c.trim().isNotEmpty).toList();
  }
}
