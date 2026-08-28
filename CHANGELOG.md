# Changelog

## 0.1.2

- Pin `ruby_llm` to `< 2.0`. RubyLLM 2.0 removes `halt` and decomposes the agentic loop into
  `ask_later`/`generate`/`run_tools`/`step`; this gem has never run against it, and an
  unbounded constraint would have resolved new installs onto an untested major the day it
  publishes. The bound widens once the suite passes on 2.x.

## 0.1.1

First release published by GitHub Actions through RubyGems trusted publishing — no API key
exists anywhere in the pipeline. No library changes.

## 0.1.0 — experimental

First public release. The API is deliberately small but not yet stable: artifact ordering,
error types, and trace serialization all changed shortly before this release. Pin an exact
version, and read [docs/DECISIONS.md](docs/DECISIONS.md) for what the gem refuses to do and
why — those refusals are the stable part.

### Added

- Named immutable artifact versions with `as:`/`from:` handoffs and the thin `Team#run` API.
- Machine-readable traces: `Session#to_h`/`#to_json` with per-call and run-total best-known
  token usage; prompts and results export only with `include_content: true`.
- Typed `BudgetExceededError < CollaborationError` for budget exhaustion.
- `examples/code_review/` — parallel fan-out/fan-in with a VCR-replayed spec and a
  line comparison against the upstream plain-Ruby pattern.

### Fixed

- Artifact versions are reserved in submission order, so `artifact(name)` is deterministic
  when parallel work completes out of order.
- Non-`StandardError` crashes finalize their call as `:failed` and re-raise instead of
  leaving it `:running` with a burned budget slot.
- Fiber siblings settle before a crash propagates; thread joins no longer mask the first crash.
- A coworker instance delegating back into its own call fails with a clear error instead of
  `deadlock; recursive locking`.
- Duplicate coworkers in one `parallel` batch are rejected before reserving budget instead of
  silently dropping results.
- `share_context: false` sessions no longer record handoff inputs the coworker never received.

### Changed

- `Run#step` omitted `from:` now hands over every completed artifact, matching `Session#ask`.
- The published gem contains only `lib/`, README, CHANGELOG, and LICENSE.

### Foundation

- Coworker registry, `delegate_work`/`ask_question` tools, session call budgets,
  thread/fiber `parallel`, selected handoffs, and the Markdown trace.
