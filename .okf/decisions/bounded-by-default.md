---
type: Decision
title: A run is bounded by default
description: The library advertised spend-bounding while shipping an unbounded budget; every comparable framework caps its loop.
resource: https://github.com/jetthoughts/ruby_llm-team/blob/master/docs/DECISIONS.md
tags: [defaults, budget, safety]
timestamp: '2026-08-28T00:00:00Z'
status: accepted
---

# Decision

`Team#session` and `Team#run` default `max_calls` to `DEFAULT_MAX_CALLS` (25). An explicit
`max_calls: nil` still opts out.

# Evidence

| Framework | Default cap |
|---|---|
| OpenAI Agents SDK | `max_turns` = 10 |
| CrewAI | `max_iter` = 20–25 |
| `ruby_llm` (direct dependency) | `max_retries` = 3, `request_timeout` = 300 |
| ruby_llm-team, before this | unbounded |

Internal corroboration: all four example workflows pass an explicit number (4, 4, 6, 40).
Nobody exercised the unlimited default — it existed only in theory.

# Why 25, and how not to justify it

It is a smoke alarm, not a budget. A wrong guess costs one keyword and an error naming the
exact count and blocked coworker; no default costs an invoice.

Do **not** calibrate it against per-agent turn caps. `max_turns` and `max_iter` count turns of
one agent loop; `max_calls` counts delegation hops across a whole run, and one parallel
fan-out spends its entire batch in a single statement. The frameworks above are corroboration
that bounding is normal, not evidence for this particular number.

# Known limit

A budget on delegation is not a budget on spend: `ruby_llm` has no internal tool-call
iteration cap, so one counted hop can loop on its own tools before the budget is consulted
again.

Related: [class-registered re-entrancy](/failure-modes/class-registered-reentrancy.md), whose
residual cross-thread case this default bounds.
