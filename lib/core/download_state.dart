library;

/// Download progress and state for a model.
import 'package:flutter/foundation.dart';

@immutable
class DownloadProgress {
  final double fraction; // 0.0 .. 1.0
  final int bytesReceived;
  final int? totalBytes;
  const DownloadProgress({
    required this.fraction,
    required this.bytesReceived,
    this.totalBytes,
  });
}

enum DownloadState { idle, queued, downloading, completed, failed }

@immutable
class DownloadTask {
  final String modelId;
  final DownloadState state;
  final DownloadProgress? progress;
  final String? error;
  const DownloadTask({
    required this.modelId,
    this.state = DownloadState.idle,
    this.progress,
    this.error,
  });

  DownloadTask copyWith({
    DownloadState? state,
    DownloadProgress? progress,
    String? error,
  }) =>
      DownloadTask(
        modelId: modelId,
        state: state ?? this.state,
        progress: progress ?? this.progress,
        error: error ?? this.error,
      );
}
