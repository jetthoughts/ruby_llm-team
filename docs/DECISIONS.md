# Decisions

Status: accepted, 2026-08-28. What is settled, for a human deciding whether to depend on this.

The evidence behind each decision — reproduced failure modes, measurements, the reasoning the
code does not carry — lives in [`.okf/`](../.okf/index.md), which is written for agents. This
document is the short version. Superseded ADRs and roadmap drafts remain in git history.

## Product boundary

**Team owns** reusable coworker coordination: named roles, immutable named artifact versions
with explicit `as:`/`from:` handoffs, atomic call budgets, thread and fiber fan-out, normalized
failures, revision history, traces, and the `delegate_work`/`ask_question` tools that let a lead
model route work safely.

**Your application owns** order, routing, quality loops, escalation, validation, approvals, and
persistence.

**RubyLLM and ecosystem gems own** models, schemas, tools, MCP, provider retries, request
timeouts, and instrumentation.

## What Team refuses, and why

- **No `Crew`/`Task`/`Process`, graph DSL, YAML workflows, or role-and-backstory metaphors.**
  RubyLLM documents every one of these workflows as plain Ruby classes.
- **No generic `refine`/`repair` lifecycle.** Built, measured, removed — upstream teaches the
  same loop in fewer lines, and the two-domain evidence bar is still unmet.
- **No `parallel(limit:)`.** `tasks.each_slice(3)` at the call site is one line, and a cap
  would only narrow the window on concurrency bugs rather than fix them.
- **No memory, RAG, MCP, search, model routing, or hidden retries.** Ecosystem gems own these.
- **No dashboards, persistence, scheduling, or tenancy.** `ruby_llm-agents` owns that
  Rails-infra layer; Team composes inside it.
- **No LLM judge as a deterministic gate** — see
  [model self-assessment](../.okf/failure-modes/model-self-assessment.md).
- **`coworker` and the `delegate_work`/`ask_question` tool names stay**, deliberately. They are
  CrewAI's words; what is refused above is its *agent-definition* metaphor, not its vocabulary
  for a mechanic Team adopts.

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
looking. Mechanics for the first three are in
[`.okf/`](../.okf/index.md); the rest stand as stated.

- A budget bounds delegation hops, not provider spend, and exhaustion is loud on the Ruby path
  but quiet on the tool path — [bounded by default](../.okf/decisions/bounded-by-default.md).
- Mutual recursion across threads defeats the re-entrancy guard —
  [class-registered re-entrancy](../.okf/failure-modes/class-registered-reentrancy.md).
- `parallel` raises on the first failure and discards the batch —
  [eager Async task start](../.okf/failure-modes/eager-async-task-start.md).
- Run-total token usage sums across models. Read per-call usage when models differ.
- "Usable anywhere, including inside a Rails engine" is a claim, not evidence — every example
  is a command-line script.
- The blog example is larger than the code it saves.
- The API is pre-1.0 and moved late: artifact ordering, error types, trace serialization, and
  the read-side accessors all changed shortly before the first release.

## Bar for future growth

A new Team API must be duplicated in at least two distinct workflow domains, be smaller than the
application code it removes, and preserve Ruby's visible control flow.

**Kill switches.** If a helper's parameters grow `model:`, `schema:`, or `context:`, it has
become CrewAI's Task — stop. If an example shows Team at parity with plain Ruby, freeze the API.
If RubyLLM upstream ships session or workflow primitives, retire the overlapping surface and keep
the delegation-tools layer.
