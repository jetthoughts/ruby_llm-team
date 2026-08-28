# Decisions

Status: accepted, 2026-08-28. One record of what is settled and why.

This replaces three ADRs that argued the boundary out between them — an accepted one, a
superseded one, and a rejected one, each citing roadmap drafts that no longer exist. Their
conclusions and the evidence behind them are carried here; the originals stay in git history.

## Product boundary

**Team owns** reusable coworker coordination: named roles, immutable named artifact versions
with explicit `as:`/`from:` handoffs, atomic call budgets, thread and fiber fan-out, normalized
failures, revision history, traces, and the `delegate_work`/`ask_question` tools that let a lead
model route work safely.

**Your application owns** order, routing, quality loops, escalation, validation, approvals, and
persistence.

**RubyLLM and ecosystem gems own** models, schemas, tools, MCP, provider retries, request
timeouts, and instrumentation.

## What Team provides, and why each earns its place

- **Named artifact versions.** `result(:writer)` cannot tell a zero draft from its fifth
  revision. Versions are assigned at reservation, in submission order, so `artifact(:draft)` is
  deterministic even when parallel work completes out of order.
- **Atomic budgets with typed `BudgetExceededError`, bounded by default.** Budgets hold across
  both schedulers, and exhaustion is flagged by the session rather than inferred from message
  text. A run stops at `DEFAULT_MAX_CALLS` unless you pass `max_calls: nil`. The default is a
  smoke alarm, not a budget: it exists so a stuck loop cannot bill you forever, and a workflow
  that needs more says so in one keyword — the blog example passes 40. Do not calibrate it
  against per-agent turn caps like OpenAI's `max_turns` or CrewAI's `max_iter`; this counts
  delegation hops across a whole run, and one parallel fan-out spends its whole batch at once.
- **Failures that cannot strand a run.** Non-`StandardError` crashes finalize their call and
  re-raise instead of leaving it `:running` with a burned budget slot; fiber siblings settle
  before a crash propagates; a coworker that delegates into its own call fails with a clear
  error rather than deadlocking or recursing, whether it was registered as a class or an
  instance.
- **Handoffs a coworker cannot forge.** Relayed results are wrapped in a per-session random
  fence, so output from a fetched web page cannot impersonate a handoff from a coworker that
  never ran. The fence is the structural half of the defence; prompt wording is the weaker
  half and is not relied on alone.
- **Traces.** Markdown to read, `to_h`/`to_json` for tooling, with per-call and run-total
  best-known token usage. The exported prompt is exactly what the coworker received, context and
  handoffs included. Content is excluded unless asked for, so a trace is safe to ship.

The trace is the feature with no cheap substitute, and prompt visibility is a contract: the top
complaint about agent frameworks in production is not knowing what was actually sent.

## What Team refuses, and why

- **Keeping `coworker` and the `delegate_work`/`ask_question` tool names is deliberate.** They
  are CrewAI's words, and no other library uses them — chatwoot's `ai-agents` says `handoff`,
  Anthropic says `subagent`. What this record refuses below is CrewAI's *agent-definition*
  metaphor (role, backstory, goal), not its vocabulary for the delegation target, whose
  mechanic Team does adopt. There is no contradiction to resolve, and no evidence any human
  was ever confused by the noun.
- **No `Crew`/`Task`/`Process`, graph DSL, YAML workflows, or role-and-backstory metaphors.**
  RubyLLM documents sequential, routing, parallel, fan-out/fan-in, and evaluator-optimizer
  workflows as plain Ruby classes. Practitioners describe these metaphors as demo tools that
  cost control in production.
- **No generic `refine`/`repair` lifecycle.** Both were built, measured, and removed: upstream
  teaches the same loop in fewer lines, and only one domain ever needed them. Three example
  workflows now exist and two contain no loops at all, so the two-domain evidence bar is still
  unmet.
- **No `parallel(limit:)`.** Measured: 40 tasks do open 40 concurrent calls. But
  `tasks.each_slice(3)` at the call site is one line, nothing here fans out more than three
  ways, and a cap would only narrow the window on the concurrency bugs rather than fix them.
  Bound concurrency at the call site or with `Async::Semaphore`.
- **No memory, RAG, MCP, search, model routing, or hidden retries.** Ecosystem gems own these
  and compose through ordinary RubyLLM tools.
- **No dashboards, persistence, scheduling, or tenancy.** `ruby_llm-agents` owns that Rails-infra
  layer. Team is the plain-Ruby substrate usable anywhere, including inside such an engine.
- **No LLM judge as a deterministic gate.** A free model wrote "approve" directly above the SQL
  injection it had just reported. Verdicts that gate anything are computed in Ruby.

## How the examples own quality

Quality policy lives in the example, never in the gem.

- Loops are bounded, recheck the final attempt, and escalate to a stronger model before giving
  up. A terminal gate that discards a finished run is a bug, not strictness.
- **Outcome over output.** Deterministic checks are limited to defects a reader cannot forgive
  and that cannot go stale: code that does not parse, unresolved placeholders, and citations
  that name sources the workflow never fetched. Word counts, heading shapes, and banned-phrase
  lists are not quality — failing a run over them discards good writing.
- Judgment belongs to editor agents, including a cold reader that receives the finished article
  alone, with no draft history to make it sympathetic.
- Only roles that establish or verify evidence hold the search tool. A writer that can search
  can also truncate its tool call against `max_tokens` and fail the whole call.
- `ruby_llm-tribunal` scores outcomes after publication: deterministic assertions first, model
  judges only if those pass.

## Known weaknesses

Recorded because a boundary document that only lists wins teaches the next reader to stop
looking.

- **A budget bounds delegation hops, not provider spend.** `ruby_llm` has no internal
  tool-call iteration cap, so one call counted against `max_calls` can loop on its own tools
  before Team looks at the budget again. Treat the budget as a backstop against runaway
  *delegation*, not as a spend ceiling.
- **Budget exhaustion is loud on one path and quiet on the other.** `Session#ask` and
  `#parallel` raise `BudgetExceededError`; the `delegate_work` tool returns a result hash
  instead, so a lead model can paper over it and answer from truncated work. Check
  `calls_remaining` if that matters to you.
- **Mutual recursion across threads defeats the re-entrancy guard.** The guard is
  thread/fiber-local so that legitimate concurrent work on one role stays legal. A coworker
  that fans out through `parallel(concurrency: :threads)` back into a role still on the stack
  gets a fresh guard. No shipped example does this — it needs an app to hand coworkers the
  shared session's tools — and the default budget bounds the damage, but it is not caught.
- **Run-total token usage sums across models.** `to_h[:usage]` adds a local writer's tokens to
  a frontier model's and reports one number, while storing `model_id` per call and ignoring it.
  Read the per-call usage when models differ.
- **`parallel` raises on the first failure** and discards the batch's return value. Results
  that did succeed are still reachable through `session.value(:role)`, but the batch itself is
  lost — treat it as all-or-nothing unless you go back to the artifacts.
- **"Usable anywhere, including inside a Rails engine" is a claim, not evidence.** Every
  example is a command-line script. Nothing here yet shows a session inside a background job
  with artifacts persisted by the caller.
- **The blog example is larger than the code it saves.** It exists to prove escalation and
  bounded gates, and is the weakest advertisement for a library that claims to be smaller than
  the application code it removes.
- **The API is pre-1.0 and moved late.** Artifact ordering, error types, trace serialization,
  and the read-side accessors all changed shortly before the first release.

## Bar for future growth

A new Team API must be duplicated in at least two distinct workflow domains, be smaller than the
application code it removes, and preserve Ruby's visible control flow.

**Kill switches.** If a helper's parameters grow `model:`, `schema:`, or `context:`, it has
become CrewAI's Task — stop. If an example shows Team at parity with plain Ruby, freeze the API.
If RubyLLM upstream ships session or workflow primitives, retire the overlapping surface and keep
the delegation-tools layer.
