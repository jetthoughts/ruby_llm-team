---
type: Failure Mode
title: The model approved the SQL injection it had just reported
description: A reviewer wrote "approve" directly above its own injection finding, in one response — so verdicts moved into Ruby.
resource: https://github.com/jetthoughts/ruby_llm-team/blob/master/examples/code_review/workflow.rb
tags: [llm-reliability, gating, structured-output, observed]
timestamp: '2026-08-28T00:00:00Z'
severity: high
status: fixed
---

# Symptom

The code-review example fans three specialists over one diff and has a synthesiser merge their
findings. On a live run the synthesiser produced a headline verdict of **approve** above a
findings list whose first entry was the SQL injection it had itself reported. The model
contradicted its own structured output inside a single response.

A second observation on a later run: specialists returned `verdict: "approve"` in their schema
while simultaneously populating `findings` with real defects.

# Fix

The verdict is no longer requested from any model. It is computed in Ruby from reported
findings — any specialist reporting findings means changes are requested:

```ruby
blocking = @reviews.values.count { |review| Array(review['findings']).any? }
```

The `verdict` field was removed from the reviewer schema entirely. An unreliable field that
nothing reads is worse than no field, because its presence implies it can be trusted.

# Generalisation

A model can be an excellent *reporter* and an unreliable *judge* in the same breath. Anything
that gates a decision belongs in ordinary code reading the model's findings, never in the
model's own summary of them.

This is why the blog example's publication gate is deterministic and why
[citation provenance](/failure-modes/unverified-citations.md) is a string comparison rather
than a judging agent.

# Citations

[1] [spec/ruby_llm/code_review_workflow_spec.rb](https://github.com/jetthoughts/ruby_llm-team/blob/master/spec/ruby_llm/code_review_workflow_spec.rb)
