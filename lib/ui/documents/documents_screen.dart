import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import '../../core/engine_provider.dart';
import '../../rag/chunker.dart';
import '../../services/pdf_service.dart';
import '../providers.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  bool _ingesting = false;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(objectBoxStoreProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add PDFs to make them searchable in the current conversation.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _ingesting ? null : _pickAndIngest,
              icon: const Icon(Icons.upload_file),
              label: const Text('Pick PDF'),
            ),
            const SizedBox(height: 12),
            if (_ingesting) ...[
              LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_status),
            ],
            if (store.ready) ...[
              const SizedBox(height: 16),
              Text('Library', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Expanded(child: _DocumentList()),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndIngest() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: false,
    );
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final name = path.basename(file.path);

    setState(() {
      _ingesting = true;
      _status = 'Extracting text...';
    });

    final text = await PdfService.extractText(file);
    if (text.trim().isEmpty) {
      setState(() {
        _ingesting = false;
        _status = 'No text found in PDF.';
      });
      return;
    }

    setState(() => _status = 'Chunking...');
    final chunks = const Chunker().split(text);

    final engine = ref.read(llamaEngineProvider);
    final store = ref.read(objectBoxStoreProvider);

    setState(() => _status = 'Embedding ${chunks.length} chunks...');
    await store.ingestChunks(
      engine,
      name,
      chunks,
      global: false,
      onProgress: (done, total) => setState(() => _status = 'Embedded $done / $total'),
    );

    setState(() {
      _ingesting = false;
      _status = 'Ingested ${chunks.length} chunks from $name';
    });
  }
}

class _DocumentList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(objectBoxStoreProvider);
    // Simple grouping by source name.
    final query = store.box.query().build();
    final docs = query.find();
    query.close();

    final bySource = <String, int>{};
    for (final d in docs) {
      bySource[d.sourceName] = (bySource[d.sourceName] ?? 0) + 1;
    }
    final names = bySource.keys.toList()..sort();

    return ListView.builder(
      itemCount: names.length,
      itemBuilder: (context, index) {
        final name = names[index];
        return ListTile(
          title: Text(name),
          subtitle: Text('${bySource[name]} chunks'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              store.deleteBySource(name);
            },
          ),
        );
      },
    );
  }
}
