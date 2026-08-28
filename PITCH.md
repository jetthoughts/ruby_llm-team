# PITCH: `ruby_llm-team`

`ruby_llm-team` packages the repeated plumbing around named RubyLLM coworkers:
delegation tools, exact result handoffs, bounded calls, concurrent review, and an
inspectable collaboration record. It is a small extension to RubyLLM, not a process
engine.

## Why a separate gem

RubyLLM's Agentic Workflows guidance intentionally uses ordinary Ruby for sequencing,
routing, parallel work, fan-in, and evaluator/reviser loops. The maintainer closed the
original Team contribution to RubyLLM core for that reason: the demonstrated workflows
did not justify another core abstraction.

That decision sets the boundary for this gem. Team must remove repeated integration code
without taking workflow policy away from the application.

## What the CrewAI review actually shows

CrewAI offers two related layers:

- **Crews** organize autonomous agents into sequential or hierarchical processes.
- **Flows** give the application explicit, event-driven control over state, branches, and
  execution paths.

CrewAI tasks can name an agent, expected output, prior task context, guardrails, and
asynchronous execution. A later task that depends on asynchronous tasks forms a clear
fan-out/fan-in boundary. These are useful collaboration mechanics, independent of
CrewAI's larger framework.

The review does **not** support describing CrewAI as simply rigid or claiming that its
framework decides every execution path. CrewAI itself recommends Crews for autonomous
work, Flows for deterministic work, and a hybrid for applications needing both.

## What Team adopts

- Named specialists with explicit responsibilities.
- Exact outputs from completed work as inputs to dependent work.
- Concurrent execution for independent tasks, followed by a synchronization barrier.
- Artifact-preserving reviewer handoffs with application-owned revision limits.
- Visible call limits, errors, inputs, and results.
- A choice between application-directed calls and model-directed delegation tools.

These mechanics map naturally to Ruby agents, tools, threads, and fibers. They do not
require a second workflow language.

## What Team deliberately leaves out

- `Crew` / `Task` / `Process` or graph DSLs.
- YAML workflow definitions and generated project structure.
- A built-in hierarchical manager or automatic planner.
- Framework-owned state persistence, scheduling, deployment, or remote transport.
- Built-in memory, knowledge stores, RAG, or MCP clients.
- Hidden retry, model-selection, or concurrency policy.
- Runtime quality claims based only on an LLM judge.

Those capabilities can be valuable, but RubyLLM, ordinary Ruby, and focused ecosystem
gems already provide composition points for them. Adding them to Team would turn a small
collaboration primitive into a competing agent platform.

## The product boundary

Team owns:

- a named coworker registry;
- `delegate_work` and `ask_question` tools;
- per-run collaboration state and exact handoffs;
- immutable named artifacts, revision lineage, and a thin Run API;
- atomic call budgets;
- thread or fiber fan-out/fan-in;
- normalized errors, results, and collaboration traces.

The application owns task dependencies, conditional policy, quality gates, revision and
escalation limits, persistence, authorization, cancellation, and approvals. A model may
choose coworkers through `session.tools`; explicit workflows may call `session.ask` and
`session.parallel` directly.

## Evaluation boundary

Runtime validators protect production invariants such as Ruby syntax and real APIs.
Tribunal is an optional test-time grader for relevance, faithfulness, hallucination, and
regression evaluation. Its report is evidence about a saved artifact; it is not a Team
coworker, runtime gate, or telemetry system.

## Evidence standard

Product decisions should rely on current primary documentation, source code, and observed
behavior. Anonymous community complaints may suggest questions to investigate, but they
are not sufficient evidence for permanent scope decisions.

## Sources

- [RubyLLM Agentic Workflows](https://rubyllm.com/agentic-workflows/)
- [RubyLLM Team PR discussion](https://github.com/crmne/ruby_llm/pull/891)
- [CrewAI introduction: Crews and Flows](https://docs.crewai.com/core-concepts/Agents)
- [CrewAI tasks and asynchronous context](https://docs.crewai.com/en/concepts/tasks)
- [CrewAI source](https://github.com/crewAIInc/crewAI)
- [RubyLLM ecosystem](https://rubyllm.com/ecosystem/)
