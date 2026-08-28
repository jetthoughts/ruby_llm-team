---
type: Failure Mode
title: A safety guard that missed the path every example used
description: Re-entrancy protection sat behind an early return, so class-registered coworkers recursed 51 levels deep while the changelog advertised the fix.
resource: https://github.com/jetthoughts/ruby_llm-team/blob/master/lib/ruby_llm/team.rb
tags: [concurrency, recursion, documentation-drift, reproduced]
timestamp: '2026-08-28T00:00:00Z'
severity: high
status: fixed
---

# Symptom

A coworker delegating into its own session was supposed to fail fast. The guard was a
per-agent mutex checked with `owned?` — but `ask_agent` returned *before* that check when the
agent was registered as a class:

```ruby
return agent.new.ask(prompt) if agent.is_a?(Class)   # guard never reached
```

A probe recursed **51 levels deep with no exception**, each level a real paid provider call.
On an unbounded session that is unbounded spend.

# Why it mattered more than it looked

Every example in the repository registers classes, and the README teaches classes. So the
guard covered the mode nobody used and missed the mode everybody used — while `CHANGELOG.md`
advertised the protection as fixed and the decision record stated it unconditionally.

# Fix

Protection became a property of the *role* rather than of the registration mode, tracked in
fiber-local state so genuinely concurrent work on one role stays legal while a nested call
inside one fiber or thread is refused.

# Residual weakness

Because the tracking is fiber-local by design, mutual recursion across threads — A delegates
to B, B fans out through `parallel(concurrency: :threads)` back into A — gets a fresh guard
and is not caught. The [bounded default budget](/decisions/bounded-by-default.md) limits the
damage. Recorded rather than fixed, because no shipped example can reach it.

# Generalisation

Prove a guard on the path your documentation recommends. A test exercising the unusual
registration mode plus a doc promising the common one is how a hole ships with a green suite.

# Citations

[1] [spec/ruby_llm/failure_modes_spec.rb](https://github.com/jetthoughts/ruby_llm-team/blob/master/spec/ruby_llm/failure_modes_spec.rb) — `fails fast when a class-registered coworker delegates back into its own call`
