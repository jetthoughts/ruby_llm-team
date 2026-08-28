---
type: Failure Mode
title: An Async crash prevented its sibling tasks from existing
description: Async starts tasks eagerly, so an exception escaping one task block aborted creation of the rest and left their reserved work permanently running.
resource: https://github.com/jetthoughts/ruby_llm-team/blob/master/lib/ruby_llm/team.rb
tags: [concurrency, async, fibers, reproduced]
timestamp: '2026-08-28T00:00:00Z'
severity: medium
status: fixed
---

# Symptom

Under `concurrency: :fibers`, when one task raised, the exception escaped during *creation* of
the remaining tasks. Siblings were never spawned, yet their budget had already been reserved,
so their calls stayed recorded as `:running` forever — visible in the trace as `_In progress_`
with no way to reach a terminal state.

Measured: `[["boom", :failed], ["slow", :running]]` where the thread path produced
`[["boom", :failed], ["slow", :completed]]`.

# Fix

Crashes travel as ordinary values out of each task, every task settles, and only then is the
first crash re-raised — matching the thread path's semantics:

```ruby
def crash_as_value(reservation, coworker)
  perform(reservation, coworker)
rescue Exception => e
  e
end
```

# Generalisation

A structured-concurrency primitive that "just works" on the happy path can have a completely
different failure shape from the threading model you are mentally comparing it against. Write
the crashing test for every scheduler you support, not just the default one.

Related: the same audit found that joining sibling threads could mask the first crash, since
`Thread#join` re-raises.

# Adjacent limitation

`parallel` raises on the first failure and discards the batch's return value. Results that did
succeed remain reachable through `session.value(:role)`, but the batch itself is lost — so
treat it as all-or-nothing unless you go back to the artifacts.

# Citations

[1] [spec/ruby_llm/failure_modes_spec.rb](https://github.com/jetthoughts/ruby_llm-team/blob/master/spec/ruby_llm/failure_modes_spec.rb) — `propagates a fiber crash only after every sibling call settles`
