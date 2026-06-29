import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/download_state.dart';
import '../../core/model_catalog.dart';
import '../../core/engine_provider.dart';
import '../providers.dart';

class ModelsScreen extends ConsumerWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ramAsync = ref.watch(ramInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Models')),
      body: ramAsync.when(
        data: (ramMb) => _ModelList(ramMb: ramMb),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(child: Text('Could not read device RAM')),
      ),
    );
  }
}

class _ModelList extends ConsumerStatefulWidget {
  final int ramMb;
  const _ModelList({required this.ramMb});

  @override
  ConsumerState<_ModelList> createState() => _ModelListState();
}

class _ModelListState extends ConsumerState<_ModelList> {
  final _customController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final recommended = recommendedModel(widget.ramMb);
    final recommendedSet = recommendModels(widget.ramMb).toSet();
    final models = kModelCatalog.toList()
      ..sort((a, b) {
        final ar = recommendedSet.contains(a);
        final br = recommendedSet.contains(b);
        if (ar && !br) return -1;
        if (!ar && br) return 1;
        return a.sizeBytes.compareTo(b.sizeBytes);
      });

    final engine = ref.watch(llamaEngineProvider);
    final downloadService = ref.watch(modelDownloadServiceProvider);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Detected RAM: ~${(widget.ramMb / 1024).toStringAsFixed(1)} GB',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Recommended: ${recommended.name}',
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...models.map((m) => _ModelCard(
              entry: m,
              isRecommended: m.id == recommended.id,
              isLoaded: engine.status.loadedModelId == m.id,
              task: downloadService.taskFor(m.id),
              onDownload: () => downloadService.download(m),
              onLoad: () => _loadModel(m),
            )),
        const Divider(height: 32),
        Text('Custom model URL', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _customController,
          decoration: const InputDecoration(
            hintText: 'hf://owner/repo/model.gguf',
            border: OutlineInputBorder(),
            helperText: 'Paste a Hugging Face GGUF URI',
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () {
            final uri = _customController.text.trim();
            if (uri.isNotEmpty) _downloadCustom(uri);
          },
          icon: const Icon(Icons.download),
          label: const Text('Download custom model'),
        ),
      ],
    );
  }

  Future<void> _loadModel(ModelEntry entry) async {
    final engine = ref.read(llamaEngineProvider);
    await engine.loadModel(entry);
    final settings = await ref.read(settingsStoreProvider.future);
    await settings.setDefaultModelId(entry.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${entry.name} loaded')),
      );
    }
  }

  Future<void> _downloadCustom(String uri) async {
    final engine = ref.read(llamaEngineProvider);
    // Use the generic download path through the engine manager.
    await engine.loadSource(uri);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom model cached')),
      );
    }
  }
}

class _ModelCard extends StatelessWidget {
  final ModelEntry entry;
  final bool isRecommended;
  final bool isLoaded;
  final DownloadTask task;
  final VoidCallback onDownload;
  final VoidCallback onLoad;

  const _ModelCard({
    required this.entry,
    required this.isRecommended,
    required this.isLoaded,
    required this.task,
    required this.onDownload,
    required this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    final pct = task.progress?.fraction ?? 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (isRecommended)
                  Chip(
                    label: const Text('Best for you'),
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${entry.paramsB}B • ${entry.quant} • ${entry.sizeGb.toStringAsFixed(2)} GB'),
            Text(entry.description, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            if (task.state == DownloadState.downloading) ...[
              LinearProgressIndicator(value: pct > 0 ? pct : null),
              const SizedBox(height: 4),
              Text('${(pct * 100).toStringAsFixed(1)}%'),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (task.state == DownloadState.completed || isLoaded)
                  ElevatedButton.icon(
                    onPressed: onLoad,
                    icon: Icon(isLoaded ? Icons.check : Icons.play_arrow),
                    label: Text(isLoaded ? 'Loaded' : 'Load'),
                  )
                else if (task.state == DownloadState.downloading)
                  const OutlinedButton(onPressed: null, child: Text('Downloading...'))
                else
                  ElevatedButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
