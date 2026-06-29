import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight key/value settings store.
class SettingsStore {
  static const String _firecrawlUrl = 'firecrawl_url';
  static const String _firecrawlToken = 'firecrawl_token';
  static const String _defaultModelId = 'default_model_id';
  static const String _temperature = 'temperature';
  static const String _contextSize = 'context_size';
  static const String _gpuLayers = 'gpu_layers';

  final SharedPreferences _prefs;
  SettingsStore(this._prefs);

  static Future<SettingsStore> open() async =>
      SettingsStore(await SharedPreferences.getInstance());

  String? get firecrawlUrl => _prefs.getString(_firecrawlUrl);
  Future<void> setFirecrawlUrl(String? value) async =>
      _setString(_firecrawlUrl, value);

  String? get firecrawlToken => _prefs.getString(_firecrawlToken);
  Future<void> setFirecrawlToken(String? value) async =>
      _setString(_firecrawlToken, value);

  String? get defaultModelId => _prefs.getString(_defaultModelId);
  Future<void> setDefaultModelId(String? value) async =>
      _setString(_defaultModelId, value);

  double get temperature => _prefs.getDouble(_temperature) ?? 0.7;
  Future<void> setTemperature(double value) async =>
      _prefs.setDouble(_temperature, value);

  int get contextSize => _prefs.getInt(_contextSize) ?? 4096;
  Future<void> setContextSize(int value) async =>
      _prefs.setInt(_contextSize, value);

  int get gpuLayers => _prefs.getInt(_gpuLayers) ?? 0;
  Future<void> setGpuLayers(int value) async =>
      _prefs.setInt(_gpuLayers, value);

  Future<void> _setString(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
  }
}
