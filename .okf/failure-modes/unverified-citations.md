---
type: Failure Mode
title: Nothing checked that cited sources were ever fetched
description: Agents cite URLs; every reviewer is also a model, so a plausible invented link passes every review. A set difference catches it.
resource: https://github.com/jetthoughts/ruby_llm-team/blob/master/examples/blog/workflow.rb
tags: [hallucination, provenance, deterministic-check, fixed]
timestamp: '2026-08-28T00:00:00Z'
severity: medium
status: fixed
---

# Symptom

The blog workflow researches sources, then writes an article citing them. Nothing verified
that a cited URL came from material actually fetched. Because every reviewer in the pipeline
is itself a model, a plausible invented link would pass each of them.

# Fix

A string comparison, with no model and no network call: every URL appearing in the finished
article must appear in the research artifact or in the brief handed to the workflow.

```ruby
invented = urls_in(execution.value(:published_post)) - (urls_in(@context) + fetched_urls)
```

URLs are normalised for trailing punctuation, trailing slash, and case before comparison.
Under the strict quality policy an unfetched citation fails publication; under best-effort it
becomes a disclosed warning.

# Generalisation

Some of the highest-value checks on AI output are the least clever ones. Before adding a judge
model, ask what a `Set` difference would catch. This check cannot go stale the way a
style rule can, because "do not cite what you did not fetch" is not a preference.

Contrast with [word-count gating](/decisions/outcome-over-output.md), which was deleted for
exactly the opposite reason.

# Citations

[1] [spec/ruby_llm/citation_provenance_spec.rb](https://github.com/jetthoughts/ruby_llm-team/blob/master/spec/ruby_llm/citation_provenance_spec.rb) — five specs, no model, no network
