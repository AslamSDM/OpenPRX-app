import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llamadart/llamadart.dart';
import '../../agent/agent_loop.dart';
import '../../core/device_memory.dart';
import '../../core/engine_provider.dart';
import '../../core/model_catalog.dart';
import '../../rag/rag_store.dart';
import '../providers.dart';
import 'message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  int? _conversationId;
  AgentMode _mode = AgentMode.chat;
  bool _busy = false;
  final List<ChatMessageModel> _messages = [];
  final List<AgentStep> _steps = [];
  final List<WebSource> _sources = [];

  @override
  void initState() {
    super.initState();
    _maybeLoadDefaultModel();
  }

  Future<void> _maybeLoadDefaultModel() async {
    final engine = ref.read(llamaEngineProvider);
    if (engine.status.loadedModelId != null) return;
    final ram = await DeviceMemory.totalMb();
    final recommended = recommendedModel(ram);
    final settings = await ref.read(settingsStoreProvider.future);
    final savedId = settings.defaultModelId;
    final target = (savedId != null ? findModelById(savedId) : null) ?? recommended;
    if (!mounted) return;
    await engine.loadModel(target);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    _controller.clear();

    final db = ref.read(conversationsDbProvider);
    if (_conversationId == null) {
      final conv = await db.createConversation(text);
      _conversationId = conv.id;
    } else {
      await db.touch(_conversationId!);
    }

    setState(() {
      _busy = true;
      _messages.add(ChatMessageModel(role: 'user', content: text));
      _messages.add(ChatMessageModel(role: 'assistant', content: '', streaming: true));
      _steps.clear();
      _sources.clear();
    });
    await db.addMessage(_conversationId!, 'user', text, mode: _mode.name);
    final assistantMessageId = await db.addMessage(_conversationId!, 'assistant', '', mode: _mode.name);

    final agent = ref.read(agentLoopProvider);
    final engine = ref.read(llamaEngineProvider);
    final objectBox = ref.read(objectBoxStoreProvider);

    // RAG retrieval
    List<DocChunk> ragChunks = [];
    if (objectBox.ready && _conversationId != null) {
      try {
        final embedEngine = await engine.loadSource(kDefaultEmbeddingUri);
        try {
          final vector = await embedEngine.embed(text);
          ragChunks = objectBox.retrieve(vector, conversationId: _conversationId.toString(), topK: 5);
        } finally {
          await embedEngine.dispose();
        }
      } catch (_) {
        // RAG is optional; continue without it.
      }
    }

    final history = _messages
        .where((m) => !m.streaming)
        .map((m) => LlamaChatMessage.fromText(
              role: m.role == 'user' ? LlamaChatRole.user : LlamaChatRole.assistant,
              text: m.content,
            ))
        .toList();

    final buffer = StringBuffer();
    try {
      await agent.run(AgentRunArgs(
        question: text,
        mode: _mode,
        history: history,
        conversationId: _conversationId?.toString(),
        ragContext: ragChunks,
        onToken: (token) {
          buffer.write(token);
          setState(() {
            _messages.last = ChatMessageModel(role: 'assistant', content: buffer.toString(), streaming: true);
          });
          _scrollToBottom();
        },
        onSteps: (steps) => setState(() => _steps..clear()..addAll(steps)),
        onSources: (sources) => setState(() => _sources..clear()..addAll(sources)),
      ));
    } catch (e) {
      setState(() {
        _messages.last = ChatMessageModel(role: 'assistant', content: 'Error: $e');
      });
    } finally {
      setState(() {
        _busy = false;
        _messages.last = ChatMessageModel(role: 'assistant', content: buffer.toString());
        _steps.clear();
      });
      await db.updateMessage(assistantMessageId, buffer.toString(), sourcesJson: _sourcesJson(_sources));
      _scrollToBottom();
    }
  }

  String _sourcesJson(List<WebSource> sources) {
    if (sources.isEmpty) return '';
    return sources.map((s) => '{"url":"${s.url}","title":"${s.title}"}').join(',');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final engineStatus = ref.watch(llamaEngineProvider).status;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenPRX'),
        actions: [
          _ModeChip(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (engineStatus.state != EngineState.ready && engineStatus.state != EngineState.generating)
            _EngineStatusBar(status: engineStatus),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) => MessageBubble(message: _messages[index]),
            ),
          ),
          if (_steps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: _StepsBar(steps: _steps),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'Ask anything...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _busy ? null : _send,
                  icon: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final AgentMode mode;
  final ValueChanged<AgentMode> onChanged;
  const _ModeChip({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final label = switch (mode) {
      AgentMode.chat => 'Chat',
      AgentMode.search => 'Search',
      AgentMode.research => 'Research',
    };
    return PopupMenuButton<AgentMode>(
      initialValue: mode,
      onSelected: onChanged,
      child: Chip(label: Text(label)),
      itemBuilder: (_) => [
        const PopupMenuItem(value: AgentMode.chat, child: Text('Chat')),
        const PopupMenuItem(value: AgentMode.search, child: Text('Search')),
        const PopupMenuItem(value: AgentMode.research, child: Text('Research')),
      ],
    );
  }
}

class _EngineStatusBar extends StatelessWidget {
  final dynamic status;
  const _EngineStatusBar({required this.status});

  @override
  Widget build(BuildContext context) {
    final text = switch (status.state) {
      EngineState.idle => 'No model loaded. Download a model in the Models tab.',
      EngineState.loading => 'Loading model...',
      EngineState.error => 'Model error: ${status.error ?? 'unknown'}',
      _ => null,
    };
    if (text == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.all(10),
      child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
    );
  }
}

class _StepsBar extends StatelessWidget {
  final List<AgentStep> steps;
  const _StepsBar({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: steps.map((s) {
        final icon = switch (s.status) {
          StepStatus.running => const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
          StepStatus.done => const Icon(Icons.check_circle, size: 16, color: Colors.green),
          StepStatus.failed => const Icon(Icons.error, size: 16, color: Colors.red),
        };
        return Chip(
          avatar: icon,
          label: Text(s.label, style: const TextStyle(fontSize: 12)),
        );
      }).toList(),
    );
  }
}
