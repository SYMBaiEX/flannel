# Flannel

Flannel is a local-first macOS SwiftUI app focused on private chat, model routing, knowledge retrieval, and explicit local action governance.

This repository documents a working implementation, not a roadmap-only feature list.

## Current scope

- Local-first app defaults with default local-only routing and explicit provider activation checks.
- Local and hosted provider matrix with BYOK/API, CLI, and optional bridge entries.
- Streaming path for providers with implemented transport and deterministic local fallback.
- Local model discovery for Ollama and LM Studio, with first-load discovery kick.
- In-app provider setup for endpoint/model edits, setup diagnostics, and Keychain-backed API credentials.
- Local knowledge indexing and retrieval for chat grounding.
- In-app knowledge-source onboarding for folders, files, repos, and web-page references.
- Tool/policy modeling with visible execution results and approval/blocking state.
- Message-level chat actions for pin/unpin, copy, branch-aware retry/regenerate, edit-and-rewrite, and fork, plus store-backed archive/search organization.
- Current Vercel AI SDK support remains an optional local bridge flow (`aiSDKBridge`) and is intentionally not a native Swift SDK dependency.

## Current interaction direction

- The app keeps one persistent shell across chat/artifact/settings: no top-level mode tabs for Chat/Cowork/Code are introduced in this branch.
- Left sidebar remains the primary thread/source navigator and includes quick actions (pin/favorite/archive) without breaking composer continuity.
- Main chat transcript stays the visual center; the composer remains centered and fixed while threads, artifacts, and settings are toggled.
- Right artifact rail is contextual and collapses by default; it opens for tool outputs/comparison/citation context and must not replace the active transcript or composer.
- Bottom controls are the preferred entry point for Profile/Settings and route in-window to the Models/Provider/Knowledge surfaces.
- Settings changes should return to the same thread and preserve composer input state.

## Commit-tracking discipline

- For UI architecture or screenshot-related updates, create one focused commit for each pass (or each state group if changes are independent).
- Use a granular commit style that names scope and state first, then action, e.g. `docs(ui): lock in sidebar + settings shell direction`.
- Record screenshot-linked changes in the QA doc so each commit can be traced to a visible state review path.

## Provider behavior (implemented)

- Default routing: `WorkspacePreferences.localOnlyMode = true`, and `workspace.activeProvider` filters enabled providers through local-only/cloud preference gates.
- Provider routing policies persist in `WorkspacePreferences.providerRoutingPolicy`: selected provider, local-first, best available, cheapest, and fastest. Policies only rank providers that already satisfy setup, privacy, streaming, and transport checks.
- `ChatStreamingService.streamText(for:)` is used when streaming is requested and provider config is eligible.
- Outbound context is assembled per provider by `ChatContextAssemblyService`: system instructions, optional follow-up instructions, local RAG snippets, local memories, attachment context, and recent chat turns are estimated against the selected route's context window before transport calls. In-progress streams can be stopped from the composer.
- Enabled local tools are advertised to tool-capable Ollama/OpenAI-compatible providers as function schemas. OpenAI-compatible, LM Studio, and native Ollama streamed tool-call deltas are accumulated by tool index and persisted on the assistant message for review/export. Provider-requested tools with an enabled `alwaysAllow` policy auto-run after the stream completes, append normal tool-result messages, and trigger a bounded follow-up assistant response. `askEveryTime`, `deny`, local-only, and Keychain gates still require explicit review or block execution, and manual Run/Deny controls remain available inline.
- Models settings can run a full readiness audit across every configured route, updating endpoint normalization, Keychain/CLI diagnostics, selected-model availability, discovered model caches, and per-provider status in one pass.
- If a transport is missing, malformed, or blocked by runtime policy, responses fall back to deterministic local assistant behavior.
- Subscription CLI provider rows (`subscriptionCLI`) route through local command contracts; the optional AI SDK bridge routes through a local HTTP stream contract when the bridge service is running.

## Provider matrix (capabilities and status)

- **Ollama (`localServer`)**
  - Discovery: `http://localhost:11434/api/tags`
  - Streaming: `POST /api/chat`
  - Secret: none
  - Status: implemented
- **LM Studio (`localServer`)**
  - Discovery: native `http://localhost:1234/api/v1/models`, fallback `http://localhost:1234/v1/models`
  - Streaming: OpenAI-compatible flow
  - Secret: none
  - Status: implemented
- **OpenAI / Gemini / xAI / Mistral / Groq / OpenRouter / Perplexity (`apiKey` / OpenAI-compatible transport)**
  - Streaming: OpenAI-compatible chat stream
  - Secret: required
  - Status: implemented when endpoint/model are valid
- **Anthropic (`apiKey` / `anthropicCompatible`)**
  - Streaming: Messages SSE via Anthropic-compatible endpoint
  - Secret: required
  - Status: implemented
- **ChatGPT/Codex CLI (`subscriptionCLI`)**
  - Recommended CLI contract: `codex exec --json -`.
  - Flannel executes the command as direct argv, sends the rendered chat prompt through stdin, and decodes Codex JSONL assistant events into chat text.
  - Readiness requires a user-installed/authenticated command that can answer the local `flannel-ready` smoke probe.
- **Claude Code CLI (`subscriptionCLI`)**
  - Recommended CLI contract: `claude -p --output-format stream-json --verbose`.
  - Flannel decodes Claude `json` and `stream-json` output into chat text.
  - Readiness requires a user-installed/authenticated command that can answer the local `flannel-ready` smoke probe.
- **Vercel AI SDK bridge (`aiSDKBridge`)**
  - Optional endpoint surface defaults to `http://localhost:4177/api/chat`.
  - Readiness probes `GET http://localhost:4177/api/health`; if the bridge is healthy but does not list models, Flannel validates against the configured model id.
  - Flannel sends a `flannel.ai-sdk-bridge.v1` JSON envelope with provider context, messages, tools, model, and generation overrides.
  - The bridge may return either custom `data: {"type":"text-delta" | "tool-call" | "finish"}` SSE events or OpenAI-compatible chat-completion SSE chunks.
  - No embedded AI SDK runtime is shipped in Swift.
  - The bridge is expected to be a local Node/TypeScript service when used.

## Local model discovery

- Implemented in `LocalProviderDiscoveryService`.
- The app starts discovery automatically when no discovery results exist yet, and users can refresh manually from the toolbar/model surfaces.
- Discovery targets:
  - `http://localhost:11434/api/tags`
  - `http://localhost:11434/api/ps` for best-effort loaded/running Ollama model metadata
  - `http://localhost:1234/api/v1/models`
  - fallback `http://localhost:1234/v1/models`
- Discovery updates `ProviderConfiguration.availableModels`, timestamps, `connectionStatus`, provider capabilities, missing context-window defaults, and error messages when attention is required.
- LM Studio native discovery preserves display name, publisher, context length, loaded instance count, selected variant, size, and vision/tool/reasoning capabilities.
- Ollama discovery preserves installed model metadata and enriches loaded models with context length, VRAM size, and expiry when `/api/ps` reports them.
- Models settings can pull Ollama models through `POST /api/pull`, inspect models through `POST /api/show`, and delete installed Ollama models through `DELETE /api/delete`, then refresh discovery when local model state changes.
- Embedding-only local models remain available for local RAG and are not routed as chat models.

## Keychain policy (BYOK)

- `KeychainSecretStore` holds runtime credentials only:
  - `save(_:, account:, service:)`
  - `read(_:)`
  - `delete(_:)`
- `ProviderConfiguration.secretReference` is a `KeychainSecretReference` string (`service:account`), not plaintext.
- Default service name: `flannel.ai.keys`.
- Canonical references are suggested for predictable diagnostics and reuse.
- The provider card exposes endpoint/model controls, secure API-key save, and `Check setup` diagnostics for missing endpoint/model/key and local-only/cloud routing gates.

## Streaming and local fallback behavior

- Implemented stream builders exist for:
  - Ollama
  - OpenAI Responses API
  - OpenAI-compatible providers (Gemini, xAI, Mistral, Groq, OpenRouter, Perplexity, LM Studio compatible, custom endpoints)
  - Anthropic Messages
  - local CLI process providers
- Failure reasons include missing config, unsupported mode, invalid endpoint/model/key for keyed providers, and non-2xx HTTP responses.
- On stream failure before output arrives, chat retries the next runnable provider in the active routing chain, then falls back to deterministic local behavior only after the chain is exhausted.
- Partial output is preserved and marked interrupted rather than being merged with a different model response.
- The composer exposes a Stop action while streaming and preserves partial output with a stopped marker.
- The deterministic runtime path reports explicit local-only/proxy status and never marks a remote request as sent when transport is absent.
- Assistant messages and multi-model comparison results persist run telemetry for status, provider mode, privacy scope, started/completed timestamps, latency, input/output tokens, context-window pressure where applicable, estimated API cost, and fallback reason. Ollama, OpenAI Responses, OpenAI-compatible, and Anthropic streams upgrade to provider-reported token usage when available; CLI/local fallback paths remain clearly labeled as estimates.
- Provider-requested tool calls are shown inline with function name, permission scope, provider call id, streamed argument JSON, execution status, and output preview. Completed requested tools append normal tool-result messages and trigger a follow-up response; automatic execution is limited to enabled `alwaysAllow` tools and capped by the chat continuation guard. Markdown, HTML, PDF/plaintext, and JSON exports preserve the requested call records.

## Tool execution, permissions, and results surface

- Tool entries are configured in `ToolConfiguration` and shown in the Tools surface.
- Policy modes include:
  - `alwaysAllow`
  - `askEveryTime`
  - `deny`
  - `localOnly`
- Local execution is evaluated with `LocalToolExecutionService`:
  - blocks disabled/denied items
  - blocks network tools in local-only mode
  - queues explicit approval for actions marked ask-every-time
  - resolves pending approvals from the Tools surface, including approved local reads, local file writes, terminal commands, code snippets, live web-page reads, live web search, GitHub, YouTube, and denied runs
  - returns execution results with status and effect flags.
- `LocalToolExecutionResult` exposes:
  - status (`completed`, `requiresApproval`, `blocked`, `denied`, `unavailable`)
  - `requiresApproval`, `usedNetwork`, and `modifiedFiles`
- Approved file-write requests execute a narrow UTF-8 local write contract: target path on the first line, optional `---`, and content below. Results record `modifiedFiles` and the written byte count.
- Approved terminal and code-execution requests run through local `Process` execution with a short timeout, capped output capture, explicit exit code, and approval history.
- Live web-page reader requests fetch http/https pages through `WebPageCaptureService`, extract readable text, and record `usedNetwork` while preserving local-only and ask-every-time gates.
- Web Search uses a BYOK Brave Search connector by defaulting to the LLM Context endpoint (`https://api.search.brave.com/res/v1/llm/context`), stores the subscription token in macOS Keychain, sends it as `X-Subscription-Token`, and preserves Local-Only plus ask-every-time gates before network access.
- GitHub uses a read-only REST connector for repository search/detail and issue/PR search/detail. A token can be saved in Keychain for authenticated or private-context requests; public requests can run without a token after approval.
- Notion uses a read-only BYOK connector with the current Notion API version header, stores the integration token in Keychain, and supports workspace search, page markdown retrieval by Notion URL/page ID, and data source queries after Local-Only and ask-every-time gates pass.
- YouTube is implemented as BYOK connector-backed metadata/search by video URL/id or search query, with the API key stored in Keychain and local-only/approval gates enforced. It uses official YouTube Data API metadata/search only; transcript extraction is not claimed through the official connector.
- X is implemented as a BYOK read-only connector for:
  - recent post search
  - post lookup by URL or ID
  - profile lookup by username
- X connector auth uses a bearer/API token stored in Keychain (`KeychainSecretStore`) and the same local-only + ask-every-time approval gates as other network tools.
- X is explicitly read-only: no posting or write access is claimed.
- Browser Automation is implemented as a safe native macOS default-browser opener. It accepts `open:`, `url:`, or direct http/https URLs, plus `search:` queries through DuckDuckGo by default, and preserves Local-Only plus ask-every-time gates before opening anything. It does not inspect DOM contents, click controls, submit forms, or interact with credentials.

## Chat organization

- Message rows expose compact icon actions for pin/unpin, copy, branch-aware retry/regenerate, edit-and-rewrite, and fork-from-message.
- Pinned messages render in a local rail above the current transcript.
- The active transcript has an inline Find control with match count, previous/next navigation, attachment/citation matching, and highlighted matched message rows.
- Chat history includes active/archive scopes, global chat search results, pinned-state indicators, and archive/restore actions.
- The chat shell keeps New Chat in the sidebar and command surface, while the bottom sidebar rows expose Settings plus provider/privacy status without reintroducing top-level Chat/Cowork/Code mode tabs.
- Sidebar thread rows expose pin/favorite and archive/restore as visible hover/selection actions while keeping the same context menu for folder and tag management.
- Chat templates can seed an explicit knowledge-source scope, and the Artifacts inspector exposes the current chat's knowledge scope so RAG, workspace search, and model-comparison grounding can stay limited to selected local sources.
- Chat export supports Markdown, JSON, HTML, and PDF; JSON exports can be imported back into Flannel as a fresh local chat copy with telemetry, attachments, citations, and tags preserved, while Markdown/HTML exports import as local transcript copies with roles, timestamps, and plain message text.
- Prompt profiles support local template variables for chat/system prompts, including `{{date}}`, `{{datetime}}`, `{{provider}}`, `{{model}}`, `{{provider_mode}}`, `{{privacy}}`, `{{routing_policy}}`, `{{local_only}}`, `{{thread_title}}`, `{{thread_tags}}`, `{{project}}`, `{{knowledge_source_count}}`, and `{{knowledge_sources}}`.
- Pin/archive state persists through SwiftData and reloads with the workspace.

## Workspace backup snapshots

- Per-chat exports remain available for single-thread handoff in Markdown, JSON, HTML, and PDF.
- Workspace-wide backup export/import is implemented by `WorkspaceSnapshotService` as a schema-versioned JSON payload (`schemaVersion: 1`) with stable `.flannelworkspace.json` filenames.
- Snapshot exports include the local workspace state needed for shareable backups: provider configurations, assistant threads, chat folders, prompt profiles, chat templates, model presets, knowledge sources and manifests, tool configurations and execution results, model comparison runs, pinned messages, archived thread IDs, local memories, and preferences.
- Imported snapshots reject unsupported schema versions and create a fresh local workspace identity while restoring the exported selections and workspace content.
- API key and connector secret values are not exported. Snapshots only preserve Keychain secret reference strings, so imported workspaces need matching local Keychain entries or newly saved credentials before keyed providers/tools can run.

## Local data deletion

- Storage settings include a guarded `DELETE FLANNEL DATA` reset for local workspace data.
- The reset clears chats, projects, drafts, captures, knowledge indexes, comparison runs, pinned/archive state, local memories, provider references, and tool traces, then recreates clean local defaults for provider routes, prompts, templates, knowledge placeholders, and tool permissions.
- Keychain secret values are intentionally not deleted by the workspace reset. The reset removes local secret references from the workspace; separate credential cleanup should be an explicit Keychain action.

## RAG and indexing status

- Implemented:
  - `KnowledgeSource` + manifest persistence and source status lifecycle.
  - Knowledge screen controls for adding folders, files, code repositories, and web references without editing seed data.
  - Recursive folder and code-repository indexing with deterministic file ordering, default dependency/build exclusions, user exclusion rules, file-size caps, and parent-source citations.
  - FSEvents-backed watched folder/code-repository refresh: watched sources resync on app launch, debounce local file-system changes, queue affected sources, and rebuild manifests through the same local index path.
  - Local PDF text extraction through PDFKit for searchable document snippets.
  - User-initiated web-page capture that fetches readable HTML text, stores it as a local transcript, previews the captured body, and indexes only captured page text instead of placeholder metadata.
  - `LocalKnowledgeIndexingService` with deterministic chunking and local ranking.
  - `LocalKnowledgeVectorStore` with persisted JSON vector records.
  - `WorkspaceStore.localKnowledgeRetrievalPacket(for:)` hybrid keyword/vector packet generation.
  - Thread-scoped retrieval via `AssistantThread.knowledgeSourceIDs`, so scoped chats only retrieve and cite selected knowledge sources while unscoped chats continue to use the full workspace knowledge set.
  - Command palette actions for opening Knowledge settings, rebuilding queued/stale/unindexed sources, and rebuilding every local source without adding more top-level sidebar tabs.
  - Citation block construction (`Sources`) and source-backed `AssistantMessage.citations` rendering with resolved knowledge source, manifest, status, location, chunk, vector, and match metadata in chat, comparison, and Artifacts panels.
- `KnowledgeSource.chatHistory` is seeded so local chat context can be re-grounded.
- Remaining:
  - durable scheduled URL refresh/ingest pipeline
  - learned reranking and remote-operator connector upgrades

## Run and verification commands

- `./script/build_and_run.sh`
- `./script/build_and_run.sh --verify`
- `./script/build_and_run.sh --logs`
- `./script/build_and_run.sh --telemetry`
- `./script/build_and_run.sh --debug`
- Open and run via Xcode: `open flannel.xcodeproj` then scheme `flannel`.
- Unit/integration tests (manual run):
  - `flannelTests/AIChat/ChatStreamingServiceTests.swift`
  - `flannelTests/AIChat/CLIProviderTransportTests.swift`
  - `flannelTests/AIChat/AIChatProviderRegistryTests.swift`
  - `flannelTests/AIChat/ProviderSetupServiceTests.swift`
  - `flannelTests/Assistant/AssistantRuntimeTests.swift`
  - `flannelTests/Knowledge/LocalKnowledgeIndexingServiceTests.swift`
  - `flannelTests/Knowledge/LocalEmbeddingServiceTests.swift`
  - `flannelTests/Workspace/WorkspaceStoreTests.swift`
  - `flannelTests/Workspace/WorkspaceSnapshotServiceTests.swift`
  - `flannelUITests/flannelUITests.swift` (guarded by `FLANNEL_RUN_UI_TESTS=1`)

## Specs

Detailed implementation alignment and acceptance details remain in [FLANNEL_AI_CHAT_SPEC.md](/Users/symbiex/dev/austin/flannel/flannel/docs/FLANNEL_AI_CHAT_SPEC.md).

macOS 26 chat-first layout goals and screenshot acceptance criteria are documented in [MACOS26_CHAT_UI_VISUAL_QA.md](/Users/symbiex/dev/austin/flannel/flannel/docs/MACOS26_CHAT_UI_VISUAL_QA.md).
