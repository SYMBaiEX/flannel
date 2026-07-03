# macOS 26 Chat UI Architecture and Visual QA

Last updated: 2026-06-29
Scope: documentation and screenshot acceptance criteria only. This file defines the intended chat-first UI target for Flannel and the review checklist for the deeper visual pass.

## Product shape

Flannel should read as a native macOS 26 chat workspace with controls that support, rather than compete with, the conversation.

The default layout is built from six stable regions:

1. Claude-like source-list sidebar
2. Main chat transcript
3. Centered glass composer
4. Optional artifact rail (right)
5. Bottom Settings/Profile controls
6. In-window settings mode

This is a single-window experience: sidebar/chat/composer/artifact/settings transitions should happen within the same shell.

## Primary layout

### 1. Source-list sidebar

- Left sidebar combines chat-thread list and source-list affordances.
- It is compact, scannable, and includes source/thread titles, short previews, timestamps, status labels, and quick pin/archive/search actions.
- Selecting a thread or source updates active context without remounting the shell.

### 2. Main transcript

- Main transcript is the dominant column and scrolls independently.
- Streaming appends in place and should not move composer geometry.
- Long messages, code blocks, citations, tool outputs, and attachments remain in-line in the transcript.
- Assistant responses expose compact run chips for provider, mode, privacy scope, status, token estimates, context pressure, latency, cost when available, and fallback/stopped states.
- Row actions should be compact and non-persistent.

### 3. Centered glass composer

- Composer is bottom-centered and fixed while transcript scrolls.
- Visual treatment is glass/blurred with strong contrast for input text and status chips.
- Supports multiline input, attachments, status/model cues, stop/cancel streaming, and send control without pushing transcript content.
- Empty, disabled, streaming, and fallback states use distinct visuals.

### 4. Optional artifact rail

- Right rail is optional and only for selected artifact/tool/citation context.
- It may stay collapsed by default and can be opened for detail.
- Expanded rail must not alter composer visibility or thread context.
- Content scrolls independently from transcript.
- Empty/unused rail is minimal and not promotional.
- Chat detail controls in the rail expose thread title and knowledge-source scope without becoming a second navigation sidebar.
- Multi-model comparison artifacts show provider, mode, privacy scope, latency, cost when available, token counts, and explicit estimated-token labels when provider usage is not reported.
- Artifact rail actions should be scoped and never replace the active message list.

### 5. Bottom Settings/Profile controls

- A bottom control band contains:
  - Profile action
  - Settings action
  - Local-only/cloud/tool-policy hints
- These controls open in-window settings mode instead of launching a separate modal app route.

### 6. In-window settings mode

- Entering settings replaces chat controls inside the same window shell.
- Settings mode includes provider/credentials, source and knowledge management, local-only privacy gates, and tool policies.
- Provider picker repair actions route into the in-window Models settings surface instead of opening a separate settings window.
- Models settings shows active provider, selected provider, network mode, runnable provider count, and last local discovery before the editable provider rows.
- Models settings includes a readiness audit action that checks every provider route and reports the ready vs needs-attention summary without opening another window.
- Models settings includes Ollama pull and delete controls that show progress, confirm destructive deletion, and refresh local discovery after completion.
- Models settings includes compact LM Studio load/unload controls that operate on native loaded instance IDs, avoid destructive styling, and refresh local discovery after completion.
- Local discovery rows show provider display names, canonical identifiers, publisher/family/quantization/format metadata, context length, loaded instance count, installed size, VRAM usage when reported, and capability labels without turning embedding-only models into chat routes.
- Toolbar settings search filters provider setup and local discovery rows without adding another search field.
- The top action row includes `Exit Settings`.
- Exiting must restore chat state and preserve selected thread and composer input.
- Settings should open inside the current shell and avoid introducing new modal routes.

## Commit-tracking discipline

- Scope each product UI or testing slice to its own commit and one objective.
- For every QA/test pass, append one ledger row that includes:
  - `commit:` short or full SHA
  - `slice:` what changed
  - `evidence:` screenshot file names or command outputs
  - `result:` pass / blocked
  - `reviewer:` initials or handle
- All screenshot and validation evidence must cite the commit hash that introduced the reviewed state.
- Keep docs-only polish passes separate from app-source commits.
- Prefer granular commit messages such as `docs(qc): add sidebar and settings handoff checks`.
- Avoid bundling unrelated feature changes into the same commit.

## QA commit ledger

- Use this compact format when appending new QA/testing entries:
  - `2026-06-29 | commit: <hash> | slice: <product|ui|testing> | evidence: <artifact paths + hashes> | result: <pass|blocked: reason> | reviewer: <name|handle>`

## Local-first tool approvals

- Tool execution should default to local-first behavior and make scope visible before side effects occur.
- Local file reads, local file writes, terminal commands, code execution, and connector-backed network tools must surface approval/block/deny status in plain language.
- Ask-every-time tools require an explicit approval affordance before execution.
- Network-capable tools remain blocked while local-only mode is active.
- Approved file writes and terminal/code runs should leave a visible result record with status, modified-file/network flags, and enough output to audit the action.
- Approval UI should be reachable from the chat flow and mirrored in the dedicated Tools surface; neither path may bypass the same policy gates.

## Screenshot acceptance criteria

Capture screenshots against the built macOS app, not static mockups. At minimum, keep one baseline screenshot for each state below when doing a UI polish pass.

### Required states

- Normal chat: source sidebar visible, transcript loaded, centered composer fixed, rail collapsed.
- Artifact rail review: selected artifact/tool result visible with transcript still readable.
- Long transcript: transcript scrolled mid-history with fixed composer.
- Streaming: assistant output in progress with stop control and no layout jump.
- Tool approval: pending local action with explicit approve/deny and local-only/network status.
- Settings handoff: chat route/provider issue goes to in-window settings mode and returns via `Exit Settings`.

### Layout checks

- Main chat column remains the visual priority at common desktop widths.
- Sidebar, transcript, composer, and optional rail do not overlap.
- Composer stays fixed and visible above safe-area insets.
- Rail collapse/expand preserves transcript geometry.
- Long code blocks scroll horizontally or wrap without compressing layout.
- Text labels fit in buttons, rows, and rail cards across compact and full widths.

### Visual checks

- The UI reads as native macOS: calm materials, clear hierarchy, stable spacing, and restrained accent usage.
- Chat controls use compact icon or icon-plus-label treatments where appropriate.
- Provider/privacy/tool status is legible without dominating the conversation.
- Provider routing policy is visible from the toolbar picker and Models settings, and the active provider label makes policy-routed choices distinguishable from manual selection.
- Settings content is absent from the primary chat canvas except for concise status and navigation affordances.
- Error, blocked, fallback, and approval states are visually distinct from successful assistant responses.
- Estimated token/cost chips must be labeled as estimates in both transcript metadata and comparison artifact cards, not presented as exact provider billing data.

### Interaction checks

- Sidebar and source selection updates active transcript without resetting composer state.
- Transcript scroll does not move the composer.
- Composer multiline input grows within bounded height, then scrolls internally.
- Optional rail expand/collapse keeps artifact and message context intact.
- Settings/Profile controls are always accessible at the window bottom.
- In-window settings can be entered from chat and exited via `Exit Settings`.
- Approval and denial actions update visible tool result state.
- Local-only mode blocks network tools and cloud routes consistently from chat, command palette, and Tools/settings surfaces.

## Done definition for UI screenshot updates

A UI screenshot/documentation polish pass is acceptable when:

- Screenshots cover every required state above or explicitly note a missing state with a short reason.
- Each screenshot set includes a commit reference in this file.
- README or release notes link to this QA file when screenshots are added or refreshed.
- No app source files are modified for a documentation-only pass.
- Any observed visual regressions are filed as concrete follow-up tasks with the affected region, state, and screenshot name.
