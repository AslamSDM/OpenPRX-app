import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../agent/agent_loop.dart';
import '../core/device_memory.dart';
import '../core/engine_provider.dart';
import '../core/model_download_service.dart';
import '../data/conversations_db.dart';
import '../data/settings_store.dart';
import '../rag/rag_store.dart';
import '../services/firecrawl_client.dart';

final settingsStoreProvider = FutureProvider<SettingsStore>((ref) async {
  return SettingsStore.open();
});

final conversationsDbProvider = Provider<ConversationsDatabase>((ref) {
  return ConversationsDatabase();
});

final modelDownloadServiceProvider = ChangeNotifierProvider((ref) => ModelDownloadService());

final ramInfoProvider = FutureProvider<int>((ref) async => DeviceMemory.totalMb());

final firecrawlClientProvider = Provider<FirecrawlClient?>((ref) {
  final settingsAsync = ref.watch(settingsStoreProvider);
  return settingsAsync.whenOrNull(
    data: (s) {
      final url = s.firecrawlUrl;
      if (url == null || url.isEmpty) return null;
      return FirecrawlClient(
        baseUrl: url,
        bearerToken: s.firecrawlToken,
      );
    },
  );
});

final webToolsEnabledProvider = Provider<bool>((ref) {
  final settingsAsync = ref.watch(settingsStoreProvider);
  return settingsAsync.whenOrNull(data: (s) => s.webToolsEnabled) ?? true;
});

final objectBoxStoreProvider = FutureProvider<ObjectBoxStore>((ref) async {
  final store = ObjectBoxStore();
  await store.initialize();
  return store;
});

final homeIndexProvider = StateProvider<int>((ref) => 0);

final agentLoopProvider = Provider<AgentLoop>((ref) {
  final engine = ref.watch(llamaEngineProvider);
  final firecrawl = ref.watch(firecrawlClientProvider);
  final objectBoxAsync = ref.watch(objectBoxStoreProvider);
  final objectBox = objectBoxAsync.whenOrNull(data: (s) => s);
  final webToolsEnabled = ref.watch(webToolsEnabledProvider);
  return AgentLoop(
    engine: engine,
    firecrawl: firecrawl,
    objectBox: objectBox,
    webToolsEnabled: webToolsEnabled,
  );
});
