# Code review — fan-out/fan-in on Team

Three specialist reviewers (security, performance, style) review one diff **in parallel**;
a synthesizer merges their structured findings into one prioritized review.

```sh
OPENROUTER_API_KEY=... bundle exec ruby -Ilib examples/code_review/workflow.rb [path/to.diff]
```

Defaults to [`sample.diff`](sample.diff) (a seeded SQL injection, N+1, and style problem) and a
free OpenRouter model. Saves `review.md` and the full collaboration trace to `trace.md`.
Offline and VCR-replayed specs live in `spec/ruby_llm/code_review_workflow_spec.rb`.

## Line comparison against the upstream plain-Ruby pattern

[RubyLLM's agentic-workflows guide](https://rubyllm.com/agentic-workflows/) documents this
exact shape (fan-out/fan-in `CodeReviewSystem`) as plain Ruby: agents plus an `Async` block
that awaits three reviews and asks a synthesizer. That version is ~12 lines of orchestration —
shorter than Team until it reaches production parity:

| Concern | Plain Ruby (upstream pattern) | With Team |
| --- | --- | --- |
| Fan-out + fan-in | ~12 lines (`Async` + `wait`) | `session.parallel(tasks)` — 1 line |
| Call budget across the run | hand-rolled counter + mutex (~8) | `max_calls: 4` |
| Which reviews fed the verdict | untracked | `artifact(:verdict).sources` |
| Duplicate/racy task keys | silent result loss | rejected loudly |
| Failure behavior | raw exceptions from any task | normalized `CollaborationError` after join |
| Inspectable run record | hand-rolled trace writer (~25) | `execution.to_markdown` |
| Deterministic "latest" under races | unspecified | versions ordered by submission |

Orchestration code in this example (`Workflow` class): **33 lines**. A plain-Ruby version with
the same budget, lineage, normalized failures, and trace lands around **65–75 lines** —
re-derived per project, without the concurrency guarantees pinned by this gem's specs.
The agent definitions are identical either way; Team adds nothing there on purpose.

See: [`docs/DECISIONS.md`](../../docs/DECISIONS.md) and [`docs/ROADMAP.md`](../../docs/ROADMAP.md).
