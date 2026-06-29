import 'package:dio/dio.dart';

/// Minimal client for a self-hosted Firecrawl Cloudflare Worker.
///
/// The worker exposes two endpoints:
///   POST /v1/search { query, limit }
///   POST /v1/scrape { url }
class FirecrawlClient {
  final Dio _dio;

  FirecrawlClient({required String baseUrl, String? bearerToken})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl.replaceAll(RegExp(r'/$'), ''),
          headers: bearerToken != null && bearerToken.isNotEmpty
              ? {'Authorization': 'Bearer $bearerToken'}
              : null,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ));

  bool get isConfigured => _dio.options.baseUrl.isNotEmpty;

  Future<List<WebSource>> search(String query, {int limit = 5}) async {
    final response = await _dio.post(
      '/v1/search',
      data: {'query': query, 'limit': limit},
    );
    final list = (response.data['results'] as List?) ?? [];
    return list
        .map((e) => WebSource(
              url: e['url']?.toString() ?? '',
              title: e['title']?.toString() ?? '',
              markdown: e['markdown']?.toString() ?? '',
            ))
        .where((s) => s.url.isNotEmpty)
        .toList();
  }

  Future<WebSource> scrape(String url) async {
    final response = await _dio.post(
      '/v1/scrape',
      data: {'url': url},
    );
    final data = response.data;
    return WebSource(
      url: url,
      title: data['title']?.toString() ?? '',
      markdown: data['markdown']?.toString() ?? '',
    );
  }

  Future<bool> healthCheck() async {
    try {
      final response = await _dio.get('/v1/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

class WebSource {
  final String url;
  final String title;
  final String markdown;
  WebSource({required this.url, this.title = '', this.markdown = ''});

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'markdown': markdown,
  };

  factory WebSource.fromJson(Map<String, dynamic> json) => WebSource(
        url: json['url']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        markdown: json['markdown']?.toString() ?? '',
      );
}

String sourcesBlock(List<WebSource> sources) =>
    sources.asMap().entries.map((e) {
      final i = e.key + 1;
      final s = e.value;
      return '[$i] ${s.title} (${s.url})\n${s.markdown}';
    }).join('\n\n');

String docChunkBlock(List<({String name, int seq, String text})> chunks) =>
    chunks.asMap().entries.map((e) {
      final i = e.key + 1;
      final c = e.value;
      return '[D$i] ${c.name} (chunk ${c.seq + 1}):\n${c.text}';
    }).join('\n\n');
