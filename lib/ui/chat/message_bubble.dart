import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/firecrawl_client.dart';

class ChatMessageModel {
  final String role;
  final String content;
  final bool streaming;
  final List<WebSource> sources;
  ChatMessageModel({
    required this.role,
    required this.content,
    this.streaming = false,
    this.sources = const [],
  });

  ChatMessageModel copyWith({
    String? content,
    bool? streaming,
    List<WebSource>? sources,
  }) =>
      ChatMessageModel(
        role: role,
        content: content ?? this.content,
        streaming: streaming ?? this.streaming,
        sources: sources ?? this.sources,
      );

  static List<WebSource> parseSourcesJson(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(WebSource.fromJson)
          .where((s) => s.url.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}

class MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: message.content.isEmpty && message.streaming ? '▍' : message.content,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (message.streaming)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (!isUser && message.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: message.sources.indexed.map((e) {
                  final index = e.$1;
                  final source = e.$2;
                  return ActionChip(
                    avatar: const Icon(Icons.link, size: 14),
                    label: Text('[${index + 1}] ${source.title.isNotEmpty ? source.title : source.url}'),
                    onPressed: () => _openUrl(source.url),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
