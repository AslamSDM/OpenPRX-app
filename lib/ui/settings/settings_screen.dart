import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/engine_provider.dart';
import '../../data/settings_store.dart';
import '../providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  double _temperature = 0.7;
  int _contextSize = 4096;
  bool _webToolsEnabled = true;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsStoreProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        data: (settings) {
          _urlController.text = settings.firecrawlUrl ?? '';
          _tokenController.text = settings.firecrawlToken ?? '';
          _webToolsEnabled = settings.webToolsEnabled;
          _temperature = settings.temperature;
          _contextSize = settings.contextSize;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Firecrawl Cloudflare Worker', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Worker URL',
                  hintText: 'https://openprx-firecrawl.your-subdomain.workers.dev',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: 'App token (optional)',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Enable web tools in Chat'),
                subtitle: const Text('Lets the model run web_search / fetch_page on demand'),
                value: settings.webToolsEnabled,
                onChanged: (v) => setState(() => _webToolsEnabled = v),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _save(settings),
                child: const Text('Save web tools settings'),
              ),
              const SizedBox(height: 24),
              Text('Inference', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Temperature'),
                  Expanded(
                    child: Slider(
                      value: _temperature,
                      min: 0.0,
                      max: 1.5,
                      divisions: 30,
                      label: _temperature.toStringAsFixed(2),
                      onChanged: (v) => setState(() => _temperature = v),
                    ),
                  ),
                  Text(_temperature.toStringAsFixed(2)),
                ],
              ),
              Row(
                children: [
                  const Text('Context size'),
                  const SizedBox(width: 16),
                  ChoiceChip(
                    label: const Text('2K'),
                    selected: _contextSize == 2048,
                    onSelected: (_) => setState(() => _contextSize = 2048),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('4K'),
                    selected: _contextSize == 4096,
                    onSelected: (_) => setState(() => _contextSize = 4096),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('8K'),
                    selected: _contextSize == 8192,
                    onSelected: (_) => setState(() => _contextSize = 8192),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Model', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ListTile(
                title: const Text('Unload current model'),
                trailing: const Icon(Icons.eject),
                onTap: () => ref.read(llamaEngineProvider).unload(),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading settings: $e')),
      ),
    );
  }

  Future<void> _save(SettingsStore settings) async {
    await settings.setFirecrawlUrl(_urlController.text.trim());
    await settings.setFirecrawlToken(_tokenController.text.trim());
    await settings.setWebToolsEnabled(_webToolsEnabled);
    await settings.setTemperature(_temperature);
    await settings.setContextSize(_contextSize);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }
}
