import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import 'download_state.dart';
import 'model_catalog.dart';

/// Downloads and caches GGUF models via [llamadart]'s [DefaultModelDownloadManager].
///
/// One shared instance tracks all active downloads and exposes per-model
/// progress streams the UI can listen to.
class ModelDownloadService extends ChangeNotifier {
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, StreamController<DownloadProgress>> _progressControllers = {};

  DownloadTask taskFor(String modelId) =>
      _tasks.putIfAbsent(modelId, () => DownloadTask(modelId: modelId));

  Stream<DownloadProgress> progressStream(String modelId) {
    return _progressControllers
        .putIfAbsent(modelId, () => StreamController<DownloadProgress>.broadcast())
        .stream;
  }

  /// Start downloading [entry] using its Hugging Face URI.
  ///
  /// If the file is already cached, the call completes quickly.
  Future<void> download(ModelEntry entry) async {
    if (taskFor(entry.id).state == DownloadState.downloading) return;

    _updateTask(entry.id, state: DownloadState.queued);

    final cacheDir = await getApplicationCacheDirectory();
    final downloadManager = DefaultModelDownloadManager.auto(
      appPrivateCacheDirectory: cacheDir.path,
      namespace: 'openprx',
    );
    final engine = LlamaEngine(LlamaBackend(), modelDownloadManager: downloadManager);

    try {
      _updateTask(entry.id, state: DownloadState.downloading);
      await engine.loadModelSource(
        ModelSource.parse(entry.hfUri),
        options: ModelLoadOptions(cachePolicy: ModelCachePolicy.preferCached),
        onProgress: (progress) {
          final fraction = progress.fraction;
          final dp = DownloadProgress(
            fraction: fraction ?? 0.0,
            bytesReceived: progress.receivedBytes,
            totalBytes: progress.totalBytes,
          );
          _emitProgress(entry.id, dp);
        },
      );
      _updateTask(entry.id, state: DownloadState.completed);
    } catch (e) {
      _updateTask(entry.id, state: DownloadState.failed, error: e.toString());
    } finally {
      await engine.dispose();
    }
  }

  /// Cache-bust check: returns true if the model file is already cached.
  ///
  /// This is a best-effort lookup; the authoritative cache state lives inside
  /// the llama.cpp model download manager.
  Future<bool> isCached(String hfUri) async {
    final cacheDir = await getApplicationCacheDirectory();
    final dm = DefaultModelDownloadManager.auto(
      appPrivateCacheDirectory: cacheDir.path,
      namespace: 'openprx',
    );
    // Use a throw-away engine to probe; the manager resolves the local path.
    final engine = LlamaEngine(LlamaBackend(), modelDownloadManager: dm);
    try {
      await engine.loadModelSource(
        ModelSource.parse(hfUri),
        options: ModelLoadOptions(cachePolicy: ModelCachePolicy.preferCached),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      await engine.dispose();
    }
  }

  void _updateTask(
    String modelId, {
    DownloadState? state,
    DownloadProgress? progress,
    String? error,
  }) {
    _tasks[modelId] = taskFor(modelId).copyWith(
      state: state,
      progress: progress,
      error: error,
    );
    notifyListeners();
  }

  void _emitProgress(String modelId, DownloadProgress progress) {
    _updateTask(modelId, progress: progress);
    _progressControllers[modelId]?.add(progress);
  }

  @override
  void dispose() {
    for (final c in _progressControllers.values) {
      c.close();
    }
    super.dispose();
  }
}
