import 'package:objectbox/objectbox.dart';

/// Default embedding dimension for RAG. Must match the loaded embedding GGUF
/// model (nomic-embed-text-v1.5 uses 768).
const int kEmbeddingDimensions = 768;

@Entity()
class DocChunk {
  @Id()
  int id = 0;

  String sourceName;
  String? conversationId;
  String text;
  int seq;

  /// Conversation-scoped (false) or global library (true).
  bool global;

  @HnswIndex(
    dimensions: kEmbeddingDimensions,
    distanceType: VectorDistanceType.cosine,
    neighborsPerNode: 16,
    indexingSearchCount: 100,
  )
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;

  DocChunk({
    this.id = 0,
    required this.sourceName,
    this.conversationId,
    required this.text,
    required this.seq,
    this.global = false,
    this.embedding,
  });
}
