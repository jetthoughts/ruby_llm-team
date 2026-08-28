# Roadmap

Status: active, 2026-08-28. What is settled and why lives in [DECISIONS.md](DECISIONS.md);
superseded roadmap drafts and the ADRs they cite remain in git history.

## Now — get it installable and findable

Adoption is currently impossible: `gem 'ruby_llm-team'` does not resolve. Everything else is
downstream of that.

1. **Publish 0.1.0** as explicitly experimental. The API moved late in development (typed
   errors, submission-ordered artifact versions, `to_h`/`to_json`, `calls_remaining`), so the
   release notes must say so rather than imply stability.
2. **Add Team to [rubyllm.com/ecosystem](https://rubyllm.com/ecosystem/)** by PR. That page
   already lists Schema, MCP, Tribunal, and Monitoring; it is the highest-qualified traffic a
   single PR can reach.
3. **Publish dogfooded posts** produced by `examples/editorial_pipeline.rb`, each shipped with
   its trace. The trace is simultaneously the proof, the differentiator, and the credibility
   signal — competitors' tracing requires a cloud login.

Only then take it to r/ruby or Show HN, and lead with the pipeline rather than the gem.

## Delivered

- `examples/decision_panel/` closes the last unexercised surface: a lead model is handed
  `session.tools` and chooses its own consultations, with the budget as the only limit and the
  trace recording every choice. The tools layer has now earned its place; the kill-switch that
  would have retired it does not fire.
- Named immutable artifact versions with `as:`/`from:` handoffs, ordered by submission so
  `artifact(name)` stays deterministic under parallel completion.
- Thin `Team#run`; atomic budgets with typed `BudgetExceededError` and `calls_remaining`;
  thread and fiber fan-out where siblings settle before a crash propagates; normalized failures
  covering non-`StandardError` crashes and re-entrant delegation.
- Traces: verbatim-prompt Markdown, plus `to_h`/`to_json` with per-call and run-total
  best-known token usage and content excluded by default.
- Four worked examples — offline handoff, parallel code review, parallel research, and the
  seven-pass blog — plus `editorial_pipeline.rb` composing two teams in plain Ruby.
- Release hygiene: the package contains only tracked `lib/` files, README, CHANGELOG, LICENSE;
  CI replays recorded cassettes with no API key.

## RubyLLM 2.0

[The agentic loop is exposed](https://paolino.me/rubyllm-2-0-agentic-loop/) as `ask_later`,
`generate`, `run_tools`, `step` and `complete?`, `halt` is removed, and `chat.cancel!` works
across threads. Not yet on RubyGems; the dependency is pinned `< 2.0` until the suite runs
against it.

It operates inside one chat's tool loop, where Team coordinates across agents, so the two
compose rather than overlap. It also answers three things this project recorded as weaknesses:

1. **Budget bounds hops, not spend.** Counting `step`/`generate` within a hop becomes possible,
   so the gap in [bounded by default](../.okf/decisions/bounded-by-default.md) is addressable.
2. **Cancellation and deadlines**, deferred as non-goals, now have an upstream primitive.
3. **"Usable inside a Rails engine" is a claim, not evidence.** The one-move-per-job pattern is
   the background-job example this repository lacks — the strongest candidate for closing it.

None of this is a reason to add API. The two-domain evidence bar still applies.

## Next evidence

1. **Use the panel where a decision is currently hardcoded.** `examples/editorial_pipeline.rb`
   takes `recommendations.first` — betting on the top-ranked post without argument. Letting the
   panel weigh the analyst's candidates would put model-directed delegation inside a real
   pipeline rather than a standalone demo, and is the natural next test of whether autonomy
   beats a hardcoded pick.
2. Compare duplicated mechanics across the examples before proposing any Team API. Known
   candidate: nothing yet — the runner and research plumbing already moved to
   `examples/support/`, and the remaining duplication is domain policy.

## Open questions

- Whether `PITCH.md` still earns its place now that `DECISIONS.md` states the boundary; the two
  overlap.
- Whether the blog example is the right flagship. It is the largest example and the weakest
  advertisement: most of its bulk is editorial policy that Team deliberately does not own.
