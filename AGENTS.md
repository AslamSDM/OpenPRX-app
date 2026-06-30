# OpenPRX Mobile – Agent Notes

## Project overview

Flutter app for running local GGUF LLMs on iOS/Android with a custom agent loop,
on-device RAG (ObjectBox vector store), and optional web-search/research tools
through a user-supplied Firecrawl worker URL.

Repository: `git@github.com:AslamSDM/OpenPRX-app.git`

## Tech stack

- **Inference**: `llamadart` + `llamadart_llama_cpp_flutter`
- **Vector store**: ObjectBox (`objectbox`, `objectbox_flutter_libs`)
- **Local DB / chat history**: drift (`drift`, `drift_flutter`)
- **Settings**: `shared_preferences`
- **State**: Riverpod 2.x (`flutter_riverpod`)
- **DI**: `get_it`
- **PDF extraction**: `syncfusion_flutter_pdf`
- **HTTP**: `dio`
- **File picker / share**: `file_picker`, `share_plus`, `permission_handler`, `device_info_plus`

## Build requirements

- Flutter 3.29+ with Swift Package Manager enabled (iOS).
- iOS: deployment target 16.4 (SwiftPM companion `llamadart_llama_cpp_flutter` requires it).
- Android: `minSdk 24`, `targetSdk 36`, `compileSdk 36`, NDK 28.2.13676358.
- Several plugins (`objectbox_flutter_libs`, `file_picker`, `share_plus`) still apply the Kotlin Gradle Plugin; they build for now but will need upgrading once Flutter requires built-in Kotlin-only plugins.

### Build commands

```bash
flutter build ios --simulator          # verified passing
flutter build ios --no-codesign        # verified passing (device build, unsigned)
flutter build apk --debug              # verified passing
flutter analyze                        # verified passing
flutter test                           # verified passing
```

## Signing / deployment notes

- iOS simulator builds pass.
- iOS **device** builds compile successfully with `--no-codesign`, but a real
  deployment requires an Apple Developer Team ID / signing certificate configured
  in `ios/Runner.xcodeproj`.

## Important code conventions / gotchas

- `llamadart` `ToolDefinition` handler signature uses `ToolParams` with `getString`/`getRequiredString` and `getInt` (no `getOptionalInt`).
- `ChatSession.create` expects `List<LlamaContentPart>` (e.g. `LlamaTextContent`), not raw `List<LlamaChatMessage>`.
- `LlamaChatMessage.fromText` uses the `LlamaChatRole` enum, not string role names.
- `GenerationParams` field is `temp`, not `temperature`, and is **not** `const`.
- `ModelDownloadProgress` exposes `receivedBytes`, not `bytesReceived`.
- ObjectBox `DocChunk` vector dimension is fixed to 768 for `nomic-embed-text-v1.5`.

## Android build override

`objectbox_flutter_libs` is compiled against `android-31`, but transitive AndroidX
libraries require API 34. We force every Android subproject to `compileSdk 36` in
`android/build.gradle.kts`. Do not remove that override unless ObjectBox updates.

## Web tools / Firecrawl Worker

- Worker source lives in `worker/`. It proxies Firecrawl.dev search/scrape.
- Required env: `FIRECRAWL_API_KEY`. Optional gate: `APP_TOKEN`.
- App Settings lets the user set the Worker URL, optional bearer token, and
  toggle `web_search` / `fetch_page` tools in Chat mode.
- Search / Research modes always use the web.
- Assistant messages render citation chips (`[1]`, `[2]`) that open URLs.

## Next known work

1. Test end-to-end local chat with a downloaded GGUF model.
2. Test RAG PDF ingestion and retrieval.
3. Build iOS for a physical device and verify signing.
4. Add README user-facing docs.
5. Deploy Firecrawl Cloudflare Worker and test web search/research modes.
