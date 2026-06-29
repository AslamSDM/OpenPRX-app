import 'dart:async';
import 'dart:convert';
import 'package:llamadart/llamadart.dart';
import '../core/engine_provider.dart';
import '../rag/rag_store.dart';
import '../services/firecrawl_client.dart';

export '../services/firecrawl_client.dart' show WebSource;

/// A running agent step surfaced to the UI.
enum StepStatus { running, done, failed }

class AgentStep {
  final String label;
  StepStatus status;
  AgentStep({required this.label, this.status = StepStatus.running});
}

enum AgentMode { chat, search, research }

class AgentRunArgs {
  final String question;
  final AgentMode mode;
  final List<LlamaChatMessage> history;
  final String? conversationId;
  final List<DocChunk>? ragContext;
  final void Function(String token)? onToken;
  final void Function(List<AgentStep> steps)? onSteps;
  final void Function(List<WebSource> sources)? onSources;

  const AgentRunArgs({
    required this.question,
    required this.mode,
    required this.history,
    this.conversationId,
    this.ragContext,
    this.onToken,
    this.onSteps,
    this.onSources,
  });
}

/// Lightweight agent loop built directly on [llamadart]'s tool-calling.
///
/// The loop mirrors the existing TypeScript `engine.ts` chat/search/research
/// modes, but uses native [ToolDefinition]s instead of hand-rolled prompts.
class AgentLoop {
  final LlamaEngineManager engine;
  final FirecrawlClient? firecrawl;
  final ObjectBoxStore? objectBox;

  AgentLoop({required this.engine, this.firecrawl, this.objectBox});

  Future<void> run(AgentRunArgs args) async {
    switch (args.mode) {
      case AgentMode.chat:
        await _runChat(args);
      case AgentMode.search:
        await _runSearch(args);
      case AgentMode.research:
        await _runResearch(args);
    }
  }

  Future<void> _runChat(AgentRunArgs args) async {
    final tools = <ToolDefinition>[];
    if (firecrawl?.isConfigured == true) {
      tools.add(_webSearchTool);
      tools.add(_fetchPageTool);
    }

    final system = _buildSystemPrompt(ragChunks: args.ragContext);
    await _streamAnswer(
      system: system,
      history: args.history,
      user: args.question,
      tools: tools.isNotEmpty ? tools : null,
      onToken: args.onToken,
    );
  }

  Future<void> _runSearch(AgentRunArgs args) async {
    if (firecrawl?.isConfigured != true) {
      await _streamNoWebError(args);
      return;
    }
    final steps = [AgentStep(label: 'Searching the web')];
    args.onSteps?.call([...steps]);

    final results = await firecrawl!.search(args.question, limit: 5);
    steps[0].status = StepStatus.done;
    args.onSources?.call(results);
    args.onSteps?.call([...steps]);

    steps.add(AgentStep(label: 'Reading ${results.take(3).length} sources'));
    args.onSteps?.call([...steps]);
    final pages = await _readPages(results.take(3).toList());
    steps[1].status = StepStatus.done;
    args.onSteps?.call([...steps]);

    final system = _buildSystemPrompt(
      webSources: pages,
      ragChunks: args.ragContext,
    );
    await _streamAnswer(
      system: system,
      history: args.history,
      user: args.question,
      onToken: args.onToken,
    );
  }

  Future<void> _runResearch(AgentRunArgs args) async {
    if (firecrawl?.isConfigured != true) {
      await _streamNoWebError(args);
      return;
    }
    final steps = [
      AgentStep(label: 'Planning research'),
    ];
    args.onSteps?.call([...steps]);

    final queries = await _planQueries(args.question);
    steps[0].status = StepStatus.done;
    steps.add(AgentStep(label: 'Searching ${queries.length} angles'));
    args.onSteps?.call([...steps]);

    final seen = <String>{};
    final allSources = <WebSource>[];
    for (final q in queries) {
      final res = await firecrawl!.search(q, limit: 4);
      for (final r in res) {
        if (seen.add(r.url)) allSources.add(r);
      }
    }
    steps[1].status = StepStatus.done;
    args.onSources?.call(allSources);
    args.onSteps?.call([...steps]);

    final top = allSources.take(6).toList();
    steps.add(AgentStep(label: 'Reading ${top.length} sources'));
    args.onSteps?.call([...steps]);
    final pages = await _readPages(top);
    steps[2].status = StepStatus.done;
    args.onSteps?.call([...steps]);

    steps.add(AgentStep(label: 'Synthesizing report'));
    args.onSteps?.call([...steps]);
    final system = _buildSystemPrompt(
      webSources: pages,
      ragChunks: args.ragContext,
      research: true,
    );
    await _streamAnswer(
      system: system,
      history: args.history,
      user: 'Research question: ${args.question}',
      onToken: args.onToken,
    );
    steps[3].status = StepStatus.done;
    args.onSteps?.call([...steps]);
  }

  Future<List<String>> _planQueries(String question) async {
    try {
      final raw = await engine.generate(
        'Output ONLY a JSON array of 3-4 short web-search queries that together '
        'cover the question. No prose, no code fences.\n\nQuestion: $question',
        params: GenerationParams(maxTokens: 128, temp: 0.3),
      ).join();
      final match = RegExp(r'\[[\s\S]*?\]').firstMatch(raw);
      if (match != null) {
        final arr = jsonDecode(match.group(0)!) as List;
        final qs = arr.whereType<String>().take(4).toList();
        if (qs.isNotEmpty) return qs;
      }
    } catch (_) {
      /* fall through */
    }
    return [question];
  }

  Future<List<WebSource>> _readPages(List<WebSource> sources) async {
    if (firecrawl == null) return [];
    final settled = await Future.wait(
      sources.map((s) async {
        try {
          final scraped = await firecrawl!.scrape(s.url);
          return scraped;
        } catch (_) {
          return WebSource(url: s.url, title: s.title, markdown: '');
        }
      }),
    );
    return settled.where((s) => s.markdown.trim().isNotEmpty).toList();
  }

  Future<void> _streamAnswer({
    required String system,
    required List<LlamaChatMessage> history,
    required String user,
    List<ToolDefinition>? tools,
    void Function(String token)? onToken,
  }) async {
    final messages = [...history, LlamaChatMessage.fromText(role: LlamaChatRole.user, text: user)];
    final session = ChatSession(engine.engine!, systemPrompt: system);
    final parts = messages.map((m) => LlamaTextContent(m.content)).toList();
    await for (final chunk in session.create(
      parts,
      params: GenerationParams(maxTokens: 2048),
      tools: tools,
    )) {
      final delta = chunk.choices.firstOrNull?.delta;
      final text = delta?.content;
      if (text != null) onToken?.call(text);
    }
  }

  Future<void> _streamNoWebError(AgentRunArgs args) async {
    const msg = 'Web search is not configured. Add a Firecrawl worker URL in '
        'Settings to use Search / Research mode.';
    args.onToken?.call(msg);
  }

  String _buildSystemPrompt({
    List<WebSource>? webSources,
    List<DocChunk>? ragChunks,
    bool research = false,
  }) {
    final buf = StringBuffer();
    buf.writeln('You are OpenPRX, a helpful assistant. Be clear and concise. Use markdown.');
    if (ragChunks != null && ragChunks.isNotEmpty) {
      buf.writeln();
      buf.writeln('The following documents are provided as primary context. '
          'Cite specific chunks inline like [D1], [D2]:');
      for (final c in ragChunks.indexed) {
        buf.writeln('[D${c.$1 + 1}] ${c.$2.sourceName} (chunk ${c.$2.seq + 1}):\n${c.$2.text}');
      }
    }
    if (webSources != null && webSources.isNotEmpty) {
      buf.writeln();
      buf.writeln('The web sources below are provided as additional context. '
          'Cite claims inline like [1], [2].');
      buf.writeln();
      for (final s in webSources.indexed) {
        final i = s.$1 + 1;
        final src = s.$2;
        buf.writeln('[$i] ${src.title} (${src.url})\n${src.markdown}');
      }
    }
    if (research) {
      buf.writeln();
      buf.writeln('Write a thorough, well-structured research report with markdown headings. '
          'Cite every factual claim inline. End with a short "Key takeaways" list.');
    }
    return buf.toString();
  }

  ToolDefinition get _webSearchTool => ToolDefinition(
        name: 'web_search',
        description: 'Search the web for up-to-date information.',
        parameters: [
          ToolParam.string('query', description: 'Search query', required: true),
          ToolParam.integer('limit', description: 'Number of results (1-10)', required: false),
        ],
        handler: (params) async {
          if (firecrawl == null) return 'Web search is not configured.';
          final query = params.getRequiredString('query');
          final limit = params.getInt('limit') ?? 5;
          final results = await firecrawl!.search(query, limit: limit);
          return jsonEncode(results.map((s) => s.toJson()).toList());
        },
      );

  ToolDefinition get _fetchPageTool => ToolDefinition(
        name: 'fetch_page',
        description: 'Fetch a web page and return clean markdown content.',
        parameters: [
          ToolParam.string('url', description: 'Full URL to fetch', required: true),
        ],
        handler: (params) async {
          if (firecrawl == null) return 'Web fetch is not configured.';
          final url = params.getRequiredString('url');
          final result = await firecrawl!.scrape(url);
          return result.markdown;
        },
      );
}
