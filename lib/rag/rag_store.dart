import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/engine_provider.dart';
import '../core/model_catalog.dart';
import 'objectbox_store.dart';
import '../objectbox.g.dart';

export 'objectbox_store.dart';

/// Wraps the ObjectBox store used for on-device RAG vector search.
class ObjectBoxStore extends ChangeNotifier {
  late final Store _store;
  late final Box<DocChunk> _box;
  bool _ready = false;
  bool _disposed = false;

  bool get ready => _ready;
  Box<DocChunk> get box => _box;

  Future<void> initialize() async {
    if (_disposed) return;
    final dir = await getApplicationDocumentsDirectory();
    _store = await openStore(directory: '${dir.path}/openprx-objectbox');
    _box = _store.box<DocChunk>();
    _ready = true;
    if (!_disposed) notifyListeners();
  }

  /// Embed [chunks] and persist them. If [conversationId] is null, chunks are
  /// stored in the global library.
  Future<void> ingestChunks(
    LlamaEngineManager engine,
    String sourceName,
    List<String> chunks, {
    String? conversationId,
    bool global = false,
    void Function(int done, int total)? onProgress,
  }) async {
    if (!_ready) throw StateError('ObjectBox not initialized');

    // Switch the shared engine to the embedding model temporarily.
    final chatModelId = engine.activeModelId;
    await engine.unload();

    final embedEngine = await engine.loadSource(kDefaultEmbeddingUri);
    try {
      for (var i = 0; i < chunks.length; i++) {
        final vector = await embedEngine.embed(chunks[i]);
        if (vector.length != kEmbeddingDimensions) {
          // If the model emits a different dimension, skip rather than crash.
          continue;
        }
        final chunk = DocChunk(
          sourceName: sourceName,
          conversationId: conversationId,
          text: chunks[i],
          seq: i,
          global: global,
          embedding: vector,
        );
        _box.put(chunk);
        onProgress?.call(i + 1, chunks.length);
      }
    } finally {
      await embedEngine.dispose();
      // Reload the previous chat model if there was one.
      if (chatModelId != null) {
        final entry = findModelById(chatModelId);
        if (entry != null) await engine.loadModel(entry);
      }
    }
  }

  /// Retrieve the top-k chunks relevant to [queryVector], optionally scoped to
  /// [conversationId] or the global library.
  List<DocChunk> retrieve(
    List<double> queryVector, {
    String? conversationId,
    int topK = 5,
  }) {
    if (!_ready) return [];
    if (queryVector.length != kEmbeddingDimensions) return [];

    final condition = DocChunk_.embedding.nearestNeighborsF32(queryVector, topK);
    Query<DocChunk>? query;
    if (conversationId != null) {
      query = _box
          .query(
            condition.and(DocChunk_.conversationId.equals(conversationId)),
          )
          .build();
    } else {
      query = _box.query(condition.and(DocChunk_.global.equals(true))).build();
    }
    try {
      return query.findWithScores().map((r) => r.object).toList();
    } finally {
      query.close();
    }
  }

  /// Delete all chunks for a source.
  int deleteBySource(String sourceName, {String? conversationId}) {
    final condition = DocChunk_.sourceName.equals(sourceName);
    final scoped = conversationId != null
        ? condition.and(DocChunk_.conversationId.equals(conversationId))
        : condition;
    final query = _box.query(scoped).build();
    try {
      final ids = query.findIds();
      _box.removeMany(ids);
      return ids.length;
    } finally {
      query.close();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ready) {
      _store.close();
      _ready = false;
    }
    super.dispose();
  }
}
