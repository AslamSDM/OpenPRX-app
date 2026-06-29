library;

/// Curated catalog of GGUF models available to download from Hugging Face.
///
/// Each [ModelEntry] ships with a `hf://` URI that [llamadart] can resolve,
/// plus RAM/size metadata so the UI can recommend models based on the device's
/// available memory.
import 'package:flutter/foundation.dart';

/// A curated, on-device-friendly chat/instruct GGUF model.
@immutable
class ModelEntry {
  final String id;
  final String name;
  final String family;
  final String hfUri;
  final int paramsB;
  final String quant;
  final int sizeBytes;
  final int minRamMb;
  final String description;
  final List<String> tags;

  const ModelEntry({
    required this.id,
    required this.name,
    required this.family,
    required this.hfUri,
    required this.paramsB,
    required this.quant,
    required this.sizeBytes,
    required this.minRamMb,
    required this.description,
    this.tags = const [],
  });

  double get sizeGb => sizeBytes / (1024 * 1024 * 1024);
}

/// Default embedding model used for RAG.
const String kDefaultEmbeddingUri =
    'hf://nomic-ai/nomic-embed-text-v1.5-GGUF/nomic-embed-text-v1.5.Q4_K_M.gguf';

/// Built-in catalog. Sizes are *file* sizes, not runtime RAM use.
/// minRamMb is a conservative runtime estimate: file size + context/working
/// memory + OS overhead.
const List<ModelEntry> kModelCatalog = [
  ModelEntry(
    id: 'lfm-2.5-230m-q4',
    name: 'LFM 2.5 230M',
    family: 'lfm',
    hfUri: 'hf://LiquidAI/LFM2.5-230M-GGUF/LFM2.5-230M-Q4_0.gguf',
    paramsB: 0,
    quant: 'Q4_0',
    sizeBytes: 168_000_000,
    minRamMb: 900,
    description: 'Tinyest option. Runs on very low-end devices; quality is limited.',
    tags: ['tiny', 'fast'],
  ),
  ModelEntry(
    id: 'llama-3.2-1b-q4',
    name: 'Llama 3.2 1B Instruct',
    family: 'llama3.2',
    hfUri: 'hf://bartowski/Llama-3.2-1B-Instruct-GGUF/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    paramsB: 1,
    quant: 'Q4_K_M',
    sizeBytes: 779_000_000,
    minRamMb: 2200,
    description: 'Fastest option. Good for simple questions and low-end phones.',
    tags: ['fast', 'english'],
  ),
  ModelEntry(
    id: 'llama-3.2-3b-q4',
    name: 'Llama 3.2 3B Instruct',
    family: 'llama3.2',
    hfUri: 'hf://bartowski/Llama-3.2-3B-Instruct-GGUF/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
    paramsB: 3,
    quant: 'Q4_K_M',
    sizeBytes: 1_983_000_000,
    minRamMb: 3500,
    description: 'Best balance of speed and quality for most modern phones.',
    tags: ['recommended', 'english'],
  ),
  ModelEntry(
    id: 'qwen2.5-3b-q4',
    name: 'Qwen2.5 3B Instruct',
    family: 'qwen2.5',
    hfUri: 'hf://bartowski/Qwen2.5-3B-Instruct-GGUF/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
    paramsB: 3,
    quant: 'Q4_K_M',
    sizeBytes: 2_025_000_000,
    minRamMb: 3600,
    description: 'Strong multilingual model. Great for non-English chat.',
    tags: ['multilingual'],
  ),
  ModelEntry(
    id: 'gemma-3-4b-q4',
    name: 'Gemma 3 4B IT',
    family: 'gemma3',
    hfUri: 'hf://bartowski/Gemma-3-4B-IT-GGUF/Gemma-3-4B-IT-Q4_K_M.gguf',
    paramsB: 4,
    quant: 'Q4_K_M',
    sizeBytes: 2_580_000_000,
    minRamMb: 4300,
    description: 'High quality on flagship phones. Supports long context.',
    tags: ['quality'],
  ),
  ModelEntry(
    id: 'phi-3.5-mini-q4',
    name: 'Phi-3.5 Mini Instruct',
    family: 'phi3.5',
    hfUri: 'hf://bartowski/Phi-3.5-mini-instruct-GGUF/Phi-3.5-mini-instruct-Q4_K_M.gguf',
    paramsB: 4,
    quant: 'Q4_K_M',
    sizeBytes: 2_250_000_000,
    minRamMb: 3900,
    description: 'Compact but capable. Good reasoning for its size.',
    tags: ['reasoning'],
  ),
];

/// RAM tier used for model recommendations.
enum RamTier { low, medium, high, flagship }

/// Determine the device's RAM tier from total RAM in MB.
RamTier ramTierFromTotalMb(int totalRamMb) {
  if (totalRamMb <= 3 * 1024) return RamTier.low;
  if (totalRamMb <= 5 * 1024) return RamTier.medium;
  if (totalRamMb <= 7 * 1024) return RamTier.high;
  return RamTier.flagship;
}

/// Returns models that should run comfortably on this device, sorted from
/// smallest to largest. The first entry is the "best" practical default.
List<ModelEntry> recommendModels(int totalRamMb) {
  final eligible = kModelCatalog.where((m) => m.minRamMb <= totalRamMb).toList();
  eligible.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
  return eligible;
}

/// The single model we highlight as "recommended" for this device.
ModelEntry recommendedModel(int totalRamMb) {
  final candidates = recommendModels(totalRamMb);
  if (candidates.isEmpty) return kModelCatalog.first;
  return candidates.last; // largest model the device can comfortably run
}

ModelEntry? findModelById(String id) {
  try {
    return kModelCatalog.firstWhere((m) => m.id == id);
  } on StateError {
    return null;
  }
}
