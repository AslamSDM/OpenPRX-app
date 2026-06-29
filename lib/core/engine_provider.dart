import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import 'model_catalog.dart';

/// Current lifecycle state of the local LLM engine.
enum EngineState { idle, loading, ready, generating, error }

/// Snapshot of the engine exposed to the UI.
@immutable
class EngineStatus {
  final EngineState state;
  final String? loadedModelId;
  final String? error;
  const EngineStatus({
    this.state = EngineState.idle,
    this.loadedModelId,
    this.error,
  });

  EngineStatus copyWith({
    EngineState? state,
    String? loadedModelId,
    String? error,
  }) =>
      EngineStatus(
        state: state ?? this.state,
        loadedModelId: loadedModelId ?? this.loadedModelId,
        error: error ?? this.error,
      );
}

/// Holds the active [LlamaEngine] and exposes a Riverpod-managed status.
class LlamaEngineManager extends ChangeNotifier {
  LlamaEngine? _engine;
  EngineStatus _status = const EngineStatus();
  String? _activeModelId;

  EngineStatus get status => _status;
  LlamaEngine? get engine => _engine;
  String? get activeModelId => _activeModelId;

  /// Build a new [LlamaEngine] with the app-private model cache.
  Future<LlamaEngine> _buildEngine() async {
    final cacheDir = await getApplicationCacheDirectory();
    final downloadManager = DefaultModelDownloadManager.auto(
      appPrivateCacheDirectory: cacheDir.path,
      namespace: 'openprx',
    );
    return LlamaEngine(LlamaBackend(), modelDownloadManager: downloadManager);
  }

  /// Load a chat/instruct model by catalog id.
  Future<void> loadModel(ModelEntry entry) async {
    await unload();
    _status = _status.copyWith(state: EngineState.loading, error: null);
    notifyListeners();
    try {
      _engine = await _buildEngine();
      await _engine!.loadModelSource(
        ModelSource.parse(entry.hfUri),
        options: ModelLoadOptions(cachePolicy: ModelCachePolicy.preferCached),
      );
      _activeModelId = entry.id;
      _status = _status.copyWith(
        state: EngineState.ready,
        loadedModelId: entry.id,
        error: null,
      );
    } catch (e) {
      _status = _status.copyWith(
        state: EngineState.error,
        error: 'Failed to load model: $e',
      );
    }
    notifyListeners();
  }

  /// Load an arbitrary model source (used for custom hf:// URLs and embedding
  /// models). The returned engine is managed by the caller and must be disposed.
  Future<LlamaEngine> loadSource(String uri, {String? label}) async {
    final engine = await _buildEngine();
    await engine.loadModelSource(
      ModelSource.parse(uri),
      options: ModelLoadOptions(cachePolicy: ModelCachePolicy.preferCached),
    );
    return engine;
  }

  /// Generate streaming tokens for [prompt].
  Stream<String> generate(String prompt, {GenerationParams? params}) async* {
    final engine = _engine;
    if (engine == null) {
      throw StateError('No model loaded');
    }
    _status = _status.copyWith(state: EngineState.generating);
    notifyListeners();
    try {
      await for (final token in engine.generate(
        prompt,
        params: params ?? GenerationParams(maxTokens: 1024),
      )) {
        yield token;
      }
    } finally {
      _status = _status.copyWith(state: EngineState.ready);
      notifyListeners();
    }
  }

  /// Stream a chat completion via [ChatSession].
  Stream<String> chat(
    List<LlamaChatMessage> messages, {
    String? systemPrompt,
    GenerationParams? params,
    List<ToolDefinition>? tools,
  }) async* {
    final engine = _engine;
    if (engine == null) throw StateError('No model loaded');
    _status = _status.copyWith(state: EngineState.generating);
    notifyListeners();
    final session = ChatSession(
      engine,
      systemPrompt: systemPrompt,
    );
    try {
      final parts = messages.map((m) => LlamaTextContent(m.content)).toList();
      await for (final chunk in session.create(
        parts,
        params: params ?? GenerationParams(maxTokens: 1024),
        tools: tools,
      )) {
        final delta = chunk.choices.firstOrNull?.delta;
        final text = delta?.content;
        if (text != null) yield text;
      }
    } finally {
      _status = _status.copyWith(state: EngineState.ready);
      notifyListeners();
    }
  }

  Future<void> unload() async {
    if (_engine != null) {
      await _engine!.dispose();
      _engine = null;
    }
    _activeModelId = null;
    _status = const EngineStatus();
    notifyListeners();
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }
}

final llamaEngineProvider = ChangeNotifierProvider((ref) => LlamaEngineManager());
