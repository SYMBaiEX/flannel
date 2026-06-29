# Flannel AI Chat Product and Engineering Specification (Implementation-Aligned)

Last updated: 2026-06-29
Scope note: this document describes behavior currently in this codebase, not roadmap-only vision.

## 1. System intent

- Local-first macOS AI workspace using SwiftUI + SwiftData.
- Real-time chat with provider routing, discoverable local providers, and explicit privacy/scoping labels.
- Deterministic local operations by default when a live transport path is unavailable.
- Explicitly constrained local-only mode that must be disabled before network provider activation.

## 2. Core architectural boundary

- Storage: `WorkspaceStore` owns provider config, preferences, threads, tools, knowledge sources, and workspace snapshots.
- Workspace snapshot boundary: `WorkspaceSnapshotService` serializes/imports schema-versioned local backup payloads without reading or writing Keychain secret values.
- Runtime: `ContentView` drives send/discovery and appends message updates.
- Streaming boundary: `ChatStreamingService` handles provider transport for implemented providers.
- Local fallback boundary: `AssistantRuntime` runs deterministic local tool responses and status reporting.
- Tool boundary: `LocalToolExecutionService` gates execution, permissions, and execution result output.
- Secret boundary: `KeychainSecretStore` owns credential lifecycle.

## 3. Provider mode truth

- The chat surface includes a native provider routing picker that groups modes by intent:
  - Local: Ollama and LM Studio.
  - OpenAI / ChatGPT: official OpenAI API-key mode and ChatGPT/Codex local CLI mode.
  - Anthropic / Claude: official Anthropic API-key mode and Claude Code local CLI mode.
  - Hosted APIs: Gemini, xAI, Mistral, Groq, OpenRouter, and Perplexity rows.
  - Custom and bridge: OpenAI-compatible endpoints and the optional Vercel AI SDK bridge.
- Selecting a provider records the preferred route and enables that provider row, but local-only mode remains an explicit privacy gate. Cloud API rows can become preferred while still being blocked from active routing until local-only mode is disabled and setup is complete.
- `ProviderAccessMode.localServer`
  - Used by Ollama and LM Studio entries.
  - Requires local endpoint and selected model.
- `ProviderAccessMode.apiKey`
  - Used by hosted providers.
  - Uses keychain reference for outbound auth when transport is implemented.
- `ProviderAccessMode.subscriptionCLI`
  - Used for ChatGPT/Codex and Claude Code modes.
  - Uses local command transport; not a cloud API entitlement.
  - Validates the command contract in `ProviderSetupService`, including executable availability and Claude Code print-mode requirements.
- `ProviderAccessMode.openAICompatible`
  - Used for OpenAI-compatible hosted/custom endpoints.
- `ProviderAccessMode.anthropicCompatible`
  - Used for Anthropic-compatible messaging endpoints.
- `ProviderAccessMode.aiSDKBridge`
  - Optional local TypeScript/Node bridge path for Vercel AI SDK-style provider routing.
  - Flannel validates the bridge by probing a local health endpoint and sends chat through the bridge stream contract when ready.
  - No embedded AI SDK dependency is shipped in the native Swift process.
- External research alignment as of 2026-06-29:
  - Ollama's public API docs expose local model listing, running-model listing, pull/delete, chat streaming, embeddings, and structured-output endpoints under the native `/api/*` surface.
  - LM Studio 0.4.x recommends its native v1 REST surface at `/api/v1/*`, including `GET /api/v1/models`, while also supporting OpenAI-compatible `/v1/models`, `/v1/responses`, `/v1/chat/completions`, and `/v1/embeddings`.
  - OpenAI's current API docs recommend the Responses API for semantic streaming events, while Chat Completions SSE remains supported and streams `delta` chunks. Flannel's OpenAI-compatible transport stays on Chat Completions today because it is the shared denominator for LM Studio, Groq, OpenRouter, xAI, Gemini's compatibility endpoint, and custom endpoints.
  - Claude Code's CLI reference documents print mode (`-p` / `--print`) and `--output-format stream-json`; Flannel treats that as a local CLI contract, not as an Anthropic API-key entitlement.
  - Vercel AI SDK continues to be a strong TypeScript bridge candidate for provider fan-out, tool streaming, and RAG/middleware experiments. Flannel keeps this bridge external to Swift and marks it ready only after local endpoint validation.

## 3.1 Provider readiness contract

- A provider can be `selected` without being `active`.
- A provider is `active` only when all of the following are true:
  - it is enabled.
  - its privacy scope is allowed by `WorkspacePreferences`.
  - its endpoint/model/command/key requirements pass setup diagnostics.
  - its chat transport is implemented.
  - its readiness strategy either validates live model availability or explicitly declares a static/CLI-only readiness contract.
- Local server readiness should be live whenever possible:
  - Ollama: model list and running-model metadata from native discovery.
  - LM Studio: native `/api/v1/models` first, OpenAI-compatible `/v1/models` fallback.
- OpenAI-compatible readiness should use `/v1/models` when the endpoint can support it.
- API-key provider rows may use static model defaults when live model listing is not available or requires a provider-specific endpoint, but the UI must label that as configuration readiness rather than a full live credential check.
- Optional Keychain semantics:
  - Official hosted API-key rows require a saved Keychain reference before activation.
  - Local server rows do not require API keys.
  - Subscription CLI rows do not use provider API keys.
  - Custom OpenAI-compatible rows may have an optional Keychain key. Loopback endpoints must be runnable without a key unless the user configured one. Remote custom endpoints should strongly guide users to save a key, but the requirement depends on the provider policy.
- CLI subscription rows must not advertise provider-native tool calling until the CLI event decoder and prompt contract can round-trip structured tool calls and tool results.

## 4. Provider routing and local-only policy

- `WorkspacePreferences.localOnlyMode` defaults to `true`.
- `WorkspaceStore.activeProvider` filters enabled providers by preference gates, setup diagnostics, implemented transport, streaming support, and CLI command-contract availability when relevant.
- `WorkspacePreferences.providerRoutingPolicy` controls ranking after those runnable-provider gates:
  - `selectedProvider`: use the explicitly selected provider when runnable, then fall back safely.
  - `localFirst`: prefer local servers and local CLI providers before external APIs.
  - `bestAvailable`: rank runnable providers by capability profile, model family heuristic, context window, and privacy.
  - `cheapest`: prefer zero-marginal-cost local/CLI routes and lower configured API token prices.
  - `fastest`: prefer recent measured comparison latency, then known low-latency local/API heuristics.
- `WorkspaceStore.chatProviderFallbackChain()` exposes the full ordered retry chain for chat streaming. The chain uses the same policy ranking as `activeProvider`, respects local-only/cloud/CLI gates, and excludes providers that fail setup, transport, or streaming checks.
- Manual provider selection resets the routing policy to `selectedProvider`; choosing a policy from the provider menu or Models settings keeps provider selection and privacy gates intact.
- Models settings exposes both per-route readiness checks and a bulk readiness audit that validates every configured route against setup diagnostics, endpoint/model availability, Keychain requirements, CLI command contracts, and privacy gates.
- `ProviderPrivacyScope` includes:
  - `localOnly`
  - `externalAPI`
  - `localCLI`
  - `bridgeService`
- External provider activation requires:
  - local-only mode disabled.
  - cloud preference enabled (`allowCloudProviders`).
- Local CLI provider activation requires local-only mode disabled, but does not require cloud providers to be enabled.
- Selecting a preferred provider never silently changes privacy preferences; blocked providers remain selected but inactive until the user changes Privacy settings explicitly.
- Provider rows can exist in the matrix without live request transport.

## 5. Provider support matrix

| Provider Kind | Access Mode | Discovery | Streaming transport | Live request status |
| --- | --- | --- | --- | --- |
| Ollama | localServer | `/api/tags` | `POST /api/chat` | Implemented |
| LM Studio | localServer | `/api/v1/models` (or `/v1/models`) | OpenAI-compatible chat stream | Implemented |
| OpenAI | apiKey | model metadata + manual/default | Responses API SSE (`/v1/responses`) | Implemented |
| Gemini | apiKey | config metadata | OpenAI-compatible chat stream (`/v1beta/openai/chat/completions`) | Implemented |
| xAI | apiKey | config metadata | OpenAI-compatible chat stream (`/v1/chat/completions`) | Implemented |
| Mistral | apiKey | config metadata | OpenAI-compatible chat stream (`/v1/chat/completions`) | Implemented |
| Groq | openAICompatible | `/v1/models` | OpenAI-compatible chat stream | Implemented |
| OpenRouter | openAICompatible | `/v1/models` | OpenAI-compatible chat stream | Implemented |
| Perplexity | apiKey | config metadata | OpenAI-compatible chat stream (`/chat/completions`) | Implemented |
| Anthropic | apiKey | config metadata | Messages API SSE (`/v1/messages`) | Implemented |
| ChatGPT/Codex CLI | subscriptionCLI | PATH/command contract | Process stream transport | Implemented |
| Claude Code CLI | subscriptionCLI | PATH/command contract | Process stream transport | Implemented |
| Custom OpenAI-compatible | openAICompatible | `/v1/models` | OpenAI-compatible chat stream | Implemented |
| Vercel AI SDK bridge | aiSDKBridge | `GET /api/health` on local bridge | Local bridge SSE or OpenAI-compatible stream | Implemented native client; external bridge process required |

## 6. Streaming behavior

- Entry point: `ChatStreamingService.streamText(for:)`.
- Provider-specific request builders exist for:
  - Ollama: `/api/chat`
  - OpenAI: `/v1/responses` with `stream: true`
  - OpenAI-compatible: `/v1/chat/completions` with `stream: true`
  - Anthropic: `/v1/messages` with SSE chunks
  - CLI providers: `CLIProviderTransport` stdout streaming
  - AI SDK bridge: `POST /api/chat` by default, accepting Flannel's bridge envelope and custom or OpenAI-compatible stream events
- Multimodal routing:
  - Vision-capable Ollama routes send image attachments as native base64 `images` message fields.
  - Vision-capable OpenAI Responses routes send image attachments as `input_image` content parts.
  - Vision-capable LM Studio, Groq, OpenRouter, and custom OpenAI-compatible routes send image attachments as `image_url` content parts.
  - Vision-capable Anthropic routes send image attachments as Messages API image content blocks.
  - Providers without `supportsVision` keep attachments as local structured text context instead of sending native image bytes.
- Error handling:
  - Missing model, missing key reference, unsupported mode, invalid/missing endpoint, non-2xx responses.
  - Missing key reference is blocked before request send.
  - AI SDK bridge readiness probes `GET /api/health`; endpoints ending in `/api/chat` map to `/api/health`, and healthy bridges without a model list fall back to the configured model identifier.
- Per-message run telemetry:
  - Assistant messages persist run status (`streaming`, `completed`, `fallback`, `failed`, or `stopped`), provider access mode, privacy scope, started/completed timestamps, latency, input/output token counts, context-token count, context-window size, estimated cost, and fallback reason.
  - Chat chips and Markdown/HTML/PDF/JSON export preserve this telemetry so a saved thread can explain which provider path produced each response.
  - Ollama, OpenAI Responses, OpenAI-compatible, and Anthropic streams parse provider-reported usage chunks when those streams emit them. Missing or partial usage falls back to local token estimates and is explicitly labeled as estimated in the UI/export path.
  - Enabled local tools are sent as function schemas to tool-capable Ollama, OpenAI Responses, and OpenAI-compatible providers. The schema uses one required `query` string because Flannel's current local tool runner accepts a local natural-language/string contract per tool.
  - OpenAI Responses request history uses typed `message`, `function_call`, and `function_call_output` input items so provider-requested tool loops can continue after a local tool result.
  - OpenAI Responses `response.output_text.delta`, `response.output_item.added`, `response.function_call_arguments.delta`, and `response.completed` events are parsed as typed stream events.
  - OpenAI-compatible/LM Studio `delta.tool_calls` chunks and native Ollama `message.tool_calls` chunks are parsed as typed stream events. Partial function arguments are accumulated by tool index because provider streams can split `id`, `name`, `type`, and `arguments` across chunks.
  - Accumulated provider-requested tool calls persist on the assistant message with function name, provider call id, permission scope, argument JSON, execution status, linked tool result id, and output preview. Transcript UI and Markdown/HTML/PDF/JSON exports show these requested calls for review.
- UI behavior:
  - Stream tokens append incrementally into the assistant message.
  - The composer exposes a Stop action while a stream is active and preserves partial output with a stopped marker.
  - Chat context sent to providers is assembled by `ChatContextAssemblyService` before request construction. The assembler prioritizes system instructions, local RAG snippets, local memories, attachment context, and recent chat turns within a provider-specific prompt budget, reserving additional output space for subscription CLI routes.
  - On stream failure before any output arrives, chat retries the next provider in the ordered fallback chain. The assistant message updates its provider metadata to the route that actually answers and stores the prior failure as the fallback reason.
  - If a provider fails after emitting partial text or tool calls, the partial response is preserved and marked interrupted instead of stitching together output from a different model.
  - If all runnable providers fail or return empty streams, response transitions into the deterministic local fallback path.
- When no provider is active or transport is absent, the runtime uses deterministic local behavior and explicitly marks that no remote request was sent.

## 7. Local model discovery

- Implemented in `LocalProviderDiscoveryService`.
- Current endpoints:
  - `http://localhost:11434/api/tags`
  - `http://localhost:11434/api/ps` as a best-effort running-model status join
  - `http://localhost:1234/api/v1/models`
  - fallback `http://localhost:1234/v1/models`
- Discovery updates `ProviderConfiguration.availableModels`, `lastValidatedAt`, `connectionStatus`, `lastErrorMessage`, provider capabilities, embedding support, tool support, vision support, and missing context-window defaults when ready.
- Ollama discovery preserves installed model metadata from `/api/tags` and enriches currently loaded models with `/api/ps` fields such as context length, loaded state, VRAM size, and expiry when the local Ollama version exposes them.
- Ollama model inspection is available from Models settings via `POST /api/show`, rendering Modelfile, parameters, template, license, capabilities, and raw `model_info` metadata in a local sheet.
- LM Studio native discovery preserves display name, publisher, architecture, parameter count, quantization, file format, installed size, loaded instance count, context window, selected variant, and capability flags for vision/tool-use/reasoning. The OpenAI-compatible `/v1/models` fallback remains available when the native route is unavailable.
- Embedding-only local models are discoverable for local RAG, but they are not considered runnable chat providers and cannot be selected as the active chat model from Settings.
- Discovery starts automatically on first load when no local discovery results are present, and can still be refreshed manually.
- Discovery from chat and Settings includes both default endpoints and configured Ollama/LM Studio endpoints, with target deduplication.
- Failed discovery returns `needsAttention` with error details.
- Ollama model pulling is implemented in `LocalModelManagementService`:
  - Uses `POST /api/pull` with streamed progress updates.
  - Exposes a Models settings pull form for model name and endpoint.
  - Refreshes Ollama discovery after a pull completes so newly installed models can be selected.
- Ollama model deletion is implemented in `LocalModelManagementService`:
  - Uses `DELETE /api/delete` with the selected local model name.
  - Exposes a destructive confirmation action from Ollama discovery rows.
  - Removes deleted model names from the cached provider list before refreshing discovery.

## 8. Tool execution, permissions, and result surface

- Tool capabilities and policies are modeled in `ToolConfiguration`.
- `LocalToolExecutionService` applies gates in order:
  1) tool disabled
  2) local-only mode blocking for network tools
  3) permission policy evaluation (`alwaysAllow`, `askEveryTime`, `deny`, `localOnly`)
  4) execution result status generation
- Result payload is `LocalToolExecutionResult` and includes:
  - status (`completed`, `requiresApproval`, `blocked`, `denied`, `unavailable`)
  - `requiresApproval` flag
  - effect flags (`usedNetwork`, `modifiedFiles`)
  - query/title/output text
- The Tools surface can approve or deny pending `askEveryTime` results. Approved local read/query tools, local file writes, terminal commands, code snippets, live web-page reads, live web searches, GitHub, YouTube, X, and browser automation rerun with the original result identity; denied results are recorded as no-action denials.
- `webPageReader` accepts http/https URLs, fetches through `WebPageCaptureService`, extracts readable page text, records `usedNetwork`, and obeys local-only plus ask-every-time gates before network access.
- `webSearch` is connector-backed through Brave Search BYOK: the tool stores its API key reference in macOS Keychain, defaults to `https://api.search.brave.com/res/v1/llm/context`, sends `X-Subscription-Token`, formats returned source URLs/snippets plus LLM context, and obeys local-only plus ask-every-time gates before network access.
- `github` is connector-backed through GitHub REST: the tool defaults to `https://api.github.com`, can run public repository/issue search without a token, can read an optional Keychain token for `Authorization: Bearer ...`, sends `Accept: application/vnd.github+json` plus `X-GitHub-Api-Version`, and obeys local-only plus ask-every-time gates before network access.
- `notion` is connector-backed through the Notion API: the tool defaults to `https://api.notion.com`, requires a Keychain-stored Notion integration token, sends `Authorization: Bearer ...` plus `Notion-Version: 2026-03-11`, and supports workspace search, page-markdown retrieval, and data-source query routes without write access.
- The following tool kinds are present in the execution path:
  - `youtube` is implemented as a BYOK connector using the YouTube Data API:
    - Supports metadata/search by video URL/id, and search query lookup.
    - Reads the user-provided API key from Keychain-backed `KeychainSecretStore`.
    - Applies the same local-only gating and `askEveryTime` approval policy as other network tools.
    - Does not claim transcript extraction through the official API in current implementation.
  - `x` is implemented as a BYOK read-only connector:
    - recent post search
    - post lookup by URL or ID
    - profile lookup by username
    - reads an API/bearer token from Keychain-backed `KeychainSecretStore`
    - enforces local-only mode and `askEveryTime` approval gates before network use
    - does not claim posting/write access
  - `browserAutomation`
    - Opens explicit http/https URLs or `search:` queries in the user's default browser through AppKit `NSWorkspace`.
    - Defaults search queries to DuckDuckGo and can use a configured safe http/https search endpoint.
    - Enforces local-only mode and `askEveryTime` approval gates before opening a browser target.
    - Rejects non-http(s) schemes such as `file:` or `javascript:`.
    - Does not claim DOM inspection, page reading, click automation, form submission, or credential interaction.
- File-write approvals execute a narrow UTF-8 write contract: target path on the first line, optional `---`, and content below. Results record `modifiedFiles` and written byte count.
- Terminal and code-execution approvals run through local `Process` execution with capped output, short timeouts, explicit exit codes, and recorded approval history.
- Local and live utility tools (`workspaceSearch`, `ragRetrieval`, `webPageReader`, `localFileRead`, `localFileWrite`, `terminal`, `codeExecution`) execute and return structured tool output text for local surfaces.
- Provider-requested tool calls captured from chat streams are auditable records first. If the mapped `ToolConfiguration` is enabled and explicitly set to `alwaysAllow`, Flannel auto-runs the requested tool after the stream completes, appends a normal tool-result message, records status back on the original tool call, and starts a bounded follow-up assistant response grounded in the latest local tool result. Calls configured as `askEveryTime`, `deny`, blocked by local-only mode, or missing required Keychain material remain manual or blocked. The transcript still exposes inline Run/Deny actions; Run maps model tool names onto `ToolConfiguration` and adapts JSON arguments into Flannel's local tool-query contract.

## 9. Local-first policy in practice

- Defaults include local provider rows and local-only enforcement.
- No provider path requires local secret material in model objects; secrets are externalized by reference.
- If no provider is selected, send path goes directly to local runtime.
- Provider status is surfaced in sender output to avoid claiming remote inference occurred.

## 10. Keychain and secret policy

- `KeychainSecretStore` methods:
  - `save(_:, account:, service:)`
  - `read(_:)`
  - `delete(_:)`
- Secret references are stored as `service:account`, not plaintext keys.
- Default service key: `flannel.ai.keys`.
- Missing secret reference for an `apiKey` provider is treated as a configuration failure.

## 11. CLI-backed subscription modes

- CLI-backed entries are independent from API-key providers.
- Process execution is argv-safe (`Process`), with:
  - PATH lookup
  - command availability checks
  - timeout and cancellation
  - stdout stream handling
  - stderr capture
- Modes are local and depend on user-installed/authenticated CLIs.
- ChatGPT/Codex CLI and Claude Code CLI use the same setup report path as API-key providers, so Settings and the provider picker show the same missing command, missing executable, invalid command, or failed smoke-probe diagnostics.
- Live CLI readiness runs a short local prompt and requires a decoded `flannel-ready` response before the route is marked ready, so an installed binary is not treated as authenticated subscription access by itself.
- Claude Code CLI command contracts must use `-p` / `--print` or an explicit `{prompt}` placeholder; interactive sessions are not launched from chat.

## 12. RAG and indexing status

- Implemented foundations:
  - `KnowledgeSource` model with status/type/watch flags.
  - In-app source onboarding for folders, files, code repositories, and local web references.
  - Recursive folder/code-repository expansion indexes readable text and PDF files with deterministic ordering, default dependency/build exclusions, user exclusion rules, file-size caps, and parent source IDs preserved for citations/manifests.
  - `KnowledgeSourceWatchService` starts debounced FSEvents streams for watched folder and code-repository roots, queues changed sources, and rebuilds affected local manifests through `WorkspaceStore.rebuildKnowledgeIndexManifests(onlyQueued:)`.
  - User-triggered web-page capture via `WebPageCaptureService`, storing readable page text in a local `TranscriptRecord`.
  - Web references do not index placeholder metadata before capture; captured page body text is what enters retrieval.
  - `KnowledgeIndexManifest` persistence with source bookkeeping, fingerprints, and vector counts.
  - `LocalKnowledgeIndexingService` deterministic chunking, local scoring, snippet/citation support.
  - `LocalEmbeddingService` support for Ollama `/api/embed` and OpenAI-compatible `/v1/embeddings` request/response.
  - `LocalKnowledgeVectorStore` persisted JSON vectors with fingerprint checks.
  - `WorkspaceStore.localKnowledgeRetrievalPacket(for:)` hybrid keyword/vector retrieval for chat grounding.
  - `AssistantThread.knowledgeSourceIDs` stores an optional per-thread knowledge-source scope. Chat templates can seed it, the inspector can edit it, and chat/model-comparison/tool retrieval passes it through so cited context only comes from the selected local sources.
  - chat-time prompt injection via `retrievalPacket.promptContext`.
  - source-backed citations/`Sources` rendering in responses, comparison runs, and the Artifacts inspector with resolved source/manifest status, location, chunk, vector, and match metadata.
- Chat/history grounding:
  - `chatHistory` and `workspaceNotes` are first-class knowledge source kinds.
- Not implemented in this phase:
  - durable scheduled URL refresh jobs
  - provider-backed embedding generation scheduling
  - learned reranking

## 13. Chat actions and organization

- Implemented now:
  - Grouped provider/mode picker in the chat header, including distinct API-key and local CLI-backed rows for OpenAI/ChatGPT and Anthropic/Claude.
  - Preferred-vs-active provider status so a blocked selected provider does not silently masquerade as the active route.
  - Provider picker closed state shows both the selected provider and its live readiness reason.
  - Models settings includes a routing overview for active provider, selected provider, network mode, runnable provider count, and last local discovery.
  - Settings toolbar search filters provider rows and local discovery results by provider name, model, mode, endpoint, capability, status, and diagnostics.
  - Native current-thread export menu for Markdown, JSON, HTML, and PDF.
  - Current-chat detail in the Artifacts inspector with editable title and per-thread knowledge-source scope controls.
  - Native chat import via user-selected files. JSON imports are full-fidelity local copies with fresh thread/message IDs, active-thread selection, retained provider telemetry, attachments, citations, and tags, plus old workspace/project/folder references cleared to avoid dangling links. Markdown and HTML imports create local transcript copies with roles, timestamps, plain message text, and imported tags.
  - Attachment-aware composer with native file picker and drag/drop import for local files.
  - Persisted message attachment metadata, size/MIME/path details, safe text excerpts, and security-scoped bookmark data where macOS provides it.
  - Attachment context injection into provider prompts plus native image payloads for vision-capable Ollama, LM Studio/OpenAI-compatible, and Anthropic providers.
  - Markdown message rendering with selectable text, fenced code blocks, horizontal code scrolling, and copy-code controls.
  - Stream stop/cancel on an active assistant stream.
  - Message-row pin/unpin with persisted `PinnedAssistantMessage` state.
  - Copy message text plus attachment metadata to the macOS pasteboard.
  - Retry from the current or preceding user prompt.
  - Edit a user message by loading it back into the composer.
  - Fork a thread from a selected message into a new local branch.
- Pinned-message rail above the active transcript.
- Active/archived chat history scopes with archive/restore actions.
- Global chat search result rows across thread title, message text, attachments, and citations.
- Inline current-transcript Find searches visible message text, attachments, and citations; shows selected/total match count; provides previous/next navigation; scrolls to the selected message; and outlines matched rows without moving the fixed composer.
- Settings shell shape:
  - Bottom sidebar control band keeps Profile and Settings actions outside the chat canvas.
  - The footer provider/privacy status row opens Models & Providers settings for repair or route changes.
  - In-window settings includes `Exit Settings` and retains active thread/composer context on return.
- Current supported scope:
  - Pin/archive/search state persists through `WorkspaceStore` and SwiftData workspace reloads.
  - Retry/regenerate and edit rewind the transcript to the selected user turn before resending, preserving attachments and provider privacy routing without bypassing local-only gates.
  - Export generation is local-only file generation; it writes the current thread, attachments, citations, and provider metadata through a user-selected save panel and does not contact external providers.
  - JSON import reads a Flannel schema-versioned export from a user-selected local file and inserts it into the local workspace without contacting external providers; Markdown/HTML transcript import is also local-only and preserves readable transcript content without claiming attachment/tool/citation fidelity.
  - Per-chat exports remain available independently from workspace snapshots; they are still the supported single-thread sharing path.
  - Prompt profile templates render local workspace variables before use in chat/system prompts. Supported placeholders include `{{date}}`, `{{datetime}}`, `{{provider}}`, `{{model}}`, `{{provider_mode}}`, `{{privacy}}`, `{{routing_policy}}`, `{{local_only}}`, `{{thread_title}}`, `{{thread_tags}}`, `{{project}}`, `{{knowledge_source_count}}`, and `{{knowledge_sources}}`; unknown placeholders remain literal.
- Remaining gap:
  - PDF and third-party chat transcript importers are not yet implemented.
  - Non-image multimodal payloads such as audio/video and provider-specific PDF/document upload APIs are not yet implemented.

### 13.1 Native command palette and keyboard-first UX

- Implemented now:
  - `Command+K` opens a native command palette overlay from the chat surface.
  - The palette input is keyboard-first: it accepts rapid actions without switching focus from typing flow.
  - Search target space includes:
    - Chat actions: send/redo/retry/fork/pin, message context navigation.
    - Navigation actions: thread search/open/archival toggles, pinned rail jump targets, and sidebar traversal.
    - Model and provider actions: quick provider/model switcher, local vs remote route selection, and comparison entry points.
    - RAG actions: open Knowledge settings, rebuild queued/stale/unindexed sources, rebuild every local source, and jump to knowledge source context.
    - Export actions: markdown/json/html/pdf export trigger and export destination helpers.
    - Privacy actions: local-only mode toggle hints, cloud-provider enable/disable, and provider security diagnostics.
  - Command execution uses the same permission and local-only gates as their primary toolbar/menu actions so no palette path bypasses privacy controls.
- Send behavior:
  - `Command+Return` sends the composer message when the input is non-empty; plain `Return` remains the standard send path in the same context.
  - `Shift+Return` inserts a new line without submitting in the compose area.
- Keyboard-first expectation:
  - Palettes and compose controls preserve first-class keyboard workflow and keep mouse-free completion for routine chat operations.
  - All palette-triggered provider actions preserve explicit local-first defaults: local providers remain preferred, and any external action is blocked unless local-only mode and cloud-gating requirements are satisfied.
  - No provider secret or user transcript is transmitted to remote services unless the executed action explicitly routes through a non-local transport and local-only gating is disabled for that run.

### 13.2 Workspace snapshot export/import

- Status: implemented as a local service for shareable workspace backups.
- `WorkspaceSnapshotService.export(store:exportedAt:)` writes a `WorkspaceSnapshotPayload` with:
  - `schemaVersion: 1`
  - `exportedAt`
  - a `WorkspaceSnapshot` that records the source workspace ID, source schema version, timestamps, selected destination/selection IDs, durable workspace collections, and preferences.
- Snapshot filenames are explicit and stable: `<current-thread-slug>-workspace-<yyyyMMdd-HHmmss>.flannelworkspace.json`.
- Exported workspace state includes:
  - provider configurations
  - assistant threads
  - chat folders
  - prompt profiles
  - chat templates
  - model presets
  - knowledge sources and knowledge index manifests
  - tool configurations and local tool execution results
  - model comparison runs
  - pinned messages and archived assistant thread IDs
  - local memories
  - workspace preferences
- `WorkspaceSnapshotService.importWorkspace(from:importedAt:)` rejects unsupported schema versions and returns a local `Item` copy with a fresh workspace ID, import timestamps, restored selections when their referenced records exist, and `preferences.lastOpenedAt` set to the import time.
- Secret values are intentionally out of scope. Provider and tool configurations can retain `secretReference` strings, but actual API keys, connector tokens, and other Keychain secret values are never serialized into the snapshot. A restored workspace must use matching local Keychain entries or save replacement credentials before keyed provider/tool routes become runnable.
- Workspace snapshot import/export is separate from current-thread JSON chat import/export. Chat JSON import still creates fresh local thread/message IDs and clears old workspace/project/folder references; workspace snapshot import restores a whole workspace backup as a new local workspace copy.

### 13.3 Local workspace data deletion

- Status: implemented through Storage settings and `WorkspaceStore.resetLocalWorkspace(now:)`.
- The reset is guarded by the exact confirmation phrase `DELETE FLANNEL DATA`.
- Reset scope includes local chats, projects, drafts, captures, calendar entries, accounts, knowledge sources and manifests, local tool results, model comparison runs, pinned/archive state, local memories, provider configurations, and stored secret references.
- After reset, Flannel recreates clean local defaults for provider routes, one private starter chat, chat folders, prompt profiles, chat templates, model presets, knowledge placeholders, automations, and tool permissions.
- Keychain secret values are not deleted by this reset; deleting credential material remains a separate explicit Keychain-level action.

## 14. Multi-model comparison

- Status: implemented for runnable streaming providers.
- Implemented behavior:
  - Compare route in the main sidebar.
  - Select two to four runnable providers for one prompt run.
  - Default selection prefers the active/preferred provider order and local-preferred rows.
  - Streaming results render side-by-side in stable provider order.
  - Each result captures provider/model snapshot, status, input/output tokens, exact-versus-estimated token labeling, latency, estimated API cost, access mode, privacy scope, and error text.
  - Ollama, OpenAI-compatible, and Anthropic comparison streams preserve provider-reported usage when the provider emits it; comparison cards and inspector detail label estimated fallback counts instead of presenting them as billing-grade usage.
  - Shared RAG citations are snapshotted at run creation and shown with the result set.
  - Result cards can be selected for inspector detail, copied to the pasteboard, or used to switch the chat provider.
  - Active comparison runs can be stopped; queued/streaming result rows become explicit stopped failures.
  - Comparison creation filters through the same runnable-provider gates as chat and requires at least two providers, so local-only and setup rules are not bypassed.

## 15. Test and run matrix

- Build and run:
  - `./script/build_and_run.sh`
  - `./script/build_and_run.sh --verify`
  - `./script/build_and_run.sh --logs`
  - `./script/build_and_run.sh --telemetry`
  - `./script/build_and_run.sh --debug`
- Xcode:
  - `open flannel.xcodeproj` then scheme `flannel`
- Unit tests:
  - `flannelTests/AIChat/ChatStreamingServiceTests.swift`
  - `flannelTests/AIChat/CLIProviderTransportTests.swift`
  - `flannelTests/AIChat/AIChatProviderRegistryTests.swift`
  - `flannelTests/AIChat/ProviderSetupServiceTests.swift`
  - `flannelTests/Assistant/AssistantRuntimeTests.swift`
  - `flannelTests/Knowledge/LocalKnowledgeIndexingServiceTests.swift`
  - `flannelTests/Knowledge/LocalEmbeddingServiceTests.swift`
  - `flannelTests/Workspace/WorkspaceStoreTests.swift`
  - `flannelTests/Workspace/WorkspaceSnapshotServiceTests.swift`
- UI tests:
  - `flannelUITests/flannelUITests.swift` (guarded by `FLANNEL_RUN_UI_TESTS=1`)

## 16. Acceptance checklist

Implemented now:
- Local-first model selection and local-only policy enforcement.
- Runnable-provider gating for active chat selection, including setup diagnostics and transport availability.
- Streaming transport for implemented provider kinds: Ollama, LM Studio/custom OpenAI-compatible, OpenAI, Gemini, xAI, Mistral, Groq, OpenRouter, Perplexity, Anthropic, and local CLI providers.
- Stoppable streaming UI and bounded outbound history context.
- Message-row pin/copy/branch-aware retry/edit/fork controls, pinned-message rail, and active/archive chat history management.
- Local provider discovery for Ollama and LM Studio with endpoint/model hydration, running-model metadata, context-window backfill, and first-load discovery.
- Ollama pull-model flow from Models settings with streamed progress parsing and post-pull discovery refresh.
- In-app BYOK setup for endpoint/model editing, Keychain secret saving, and provider diagnostics.
- Deterministic fallback runtime for missing/failed streaming.
- Command palette discovery/execution for chat, navigation, provider/model, RAG, export, and privacy actions.
- Keyboard-first send path (`Command+Return` send, `Shift+Return` newline) documented and enforced via the same gating model as toolbar actions.
- Local knowledge indexing with manifests, vector persistence, hybrid retrieval, and chat grounding citations.
- Knowledge-source add/requeue controls for folders, files, code repositories, and web references, plus user-triggered web-page body capture for real RAG ingestion.
- Tool configuration and permission model (`localOnly`, network gating, policy modes).
- Structured local tool execution result object (`LocalToolExecutionResult`) in model layer.
- Dedicated Tools surface execution controls, result history, and approve/deny resolution for pending local tool runs.
- Read-only BYOK Notion workspace context connector for search, page markdown, and data-source query routes.
- Schema-versioned workspace snapshot export/import for local backup sharing, including provider/tool references, threads, folders, prompts, presets, knowledge state, comparison runs, pinned/archive state, local memories, and preferences without exporting Keychain secret values.
- Safe default-browser automation for URL opening and search, with explicit local-only/approval gates and no DOM/form-control claims.
- Provider diagnostics and setup validation for missing endpoint/model/key/reference and local-only/cloud gating.

Future milestones:
- Add richer browser session automation or DOM inspection only behind a separate explicit capability and stronger approval model.
- Upgrade approved tool-result follow-up from transcript-grounded continuation prompts to provider-native tool-result roles where the selected transport supports them.
- Add an operator/runbook and reference Node service for the local AI SDK bridge endpoint.
- Add scheduled URL refresh jobs for production RAG refresh.
- Add learned reranking on top of deterministic provider routing policies.

## 17. Known implementation limits

- Streaming capabilities are explicitly tied to current request-switch implementation; UI labels can show providers before transport is fully active.
- Gemini, xAI, Mistral, Groq, OpenRouter, Perplexity, and custom endpoint rows rely on OpenAI-compatible chat semantics; provider-specific advanced options remain future work.
- Tool execution surface is present, and live web-page reading, Brave-backed web search, GitHub REST context, Notion workspace context, YouTube metadata/search, X network lookup, and safe default-browser opening/search are implemented.
- Browser automation is intentionally limited to opening browser targets. It does not read browser state, inspect pages, click UI, fill forms, or authenticate browser sessions.

## 18. Current provider and platform references

- Apple Liquid Glass adoption guidance: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Ollama API reference: https://github.com/ollama/ollama/blob/main/docs/api.md
- LM Studio REST API endpoints: https://lmstudio.ai/docs/app/api/endpoints/rest
- OpenAI API docs for Responses, streaming, and tools: https://platform.openai.com/docs/api-reference/responses
- Claude Code CLI reference: https://docs.anthropic.com/en/docs/claude-code/cli-reference
- Vercel AI SDK documentation: https://ai-sdk.dev/docs
