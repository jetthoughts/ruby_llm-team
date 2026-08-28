# Roadmap

Status: active, 2026-08-28. What is settled and why lives in [DECISIONS.md](DECISIONS.md);
superseded roadmap drafts and the ADRs they cite remain in git history.

## Now — get it found

The gem is published and releasing itself. `gem 'ruby_llm-team'` resolves; `0.1.0`, `0.1.1`
and `0.1.2` are live, and a `v*` tag push publishes through RubyGems trusted publishing with
no credential in the pipeline. Discovery is the remaining bottleneck: downloads are zero
because nobody knows it exists.

1. **Add Team to [rubyllm.com/ecosystem](https://rubyllm.com/ecosystem/)** by PR. That page
   already lists Schema, MCP, Tribunal, Monitoring, Test and TopSecret; it is the
   highest-qualified traffic a single PR can reach, and RubyLLM 2.0 announcements are drawing
   attention to it right now.
2. **Publish dogfooded posts** produced by `examples/editorial_pipeline.rb`, each shipped with
   its trace. Source material and deduped queue rows are already staged in
   `jetthoughts.github.io` under `docs/projects/2608-ruby-llm-team/` and §14 of the content
   plan; the S2 row is being drafted on `blog/upgrade-ai-code-review-trust`.

Only then take it to r/ruby or Show HN, and lead with a working pipeline rather than the gem.

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
- Five worked examples — offline handoff, parallel code review, parallel research, the
  self-orchestrating decision panel, and the seven-pass blog — plus `editorial_pipeline.rb`
  composing two teams in plain Ruby, where the panel argues the analyst's shortlist instead of
  betting on its top row.
- Release hygiene: the package contains only tracked `lib/` files, README, CHANGELOG, LICENSE;
  CI replays recorded cassettes with no API key.
- Published to RubyGems, and releasing without credentials: a `v*` tag runs the suite, replays
  cassettes keyless, runs RuboCop, then exchanges the job's OIDC identity for a short-lived
  token. Verified twice, and the verification caught two defects a passing setup page hid —
  a non-existent action tag, and `rake release` refusing to run against a tag that already
  exists.

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

1. **Does the panel actually beat the ranking?** It now chooses which post to write, but the
   one live run confirmed the analyst's top row rather than overturning it. Autonomy that only
   agrees is cost without benefit — watch several runs before claiming it earns its calls.
2. **A session inside a background job**, with artifacts persisted by the caller. It is the
   missing evidence for the substrate claim, and RubyLLM 2.0's one-move-per-job pattern is the
   shape to copy.
3. Compare duplicated mechanics across the examples before proposing any Team API. Known
   candidate: nothing yet — the runner and research plumbing already moved to
   `examples/support/`, and the remaining duplication is domain policy.

## Open questions

- Whether `PITCH.md` still earns its place now that `DECISIONS.md` states the boundary; the two
  overlap.
- Whether the blog example is the right flagship. It is the largest example and the weakest
  advertisement: most of its bulk is editorial policy that Team deliberately does not own.
