---
type: Decision
title: Deterministic checks encode defects, not preferences
description: Word counts and heading rules were deleted after a 372-word article failed a 250–350 gate, discarding ~30 paid calls of work.
resource: https://github.com/jetthoughts/ruby_llm-team/blob/master/examples/blog/validation.rb
tags: [quality, validation, examples-policy]
timestamp: '2026-08-28T00:00:00Z'
status: accepted
---

# Decision

In the examples, deterministic validation is limited to defects a reader cannot forgive and
that cannot go stale:

- Ruby examples that do not parse (`Ripper`)
- Unresolved drafting placeholders
- `RubyLLM` constants, methods, and settings checked against the *installed* gem
- [Citations naming sources never fetched](/failure-modes/unverified-citations.md)

Removed: word ranges, required headings, banned-phrase lists, sentence-rhythm statistics.

# What triggered it

A generated article failed publication at 372 words against a 250–350 rule, after roughly
thirty paid model calls had produced it and every judgment gate had passed. The rule discarded
finished work over a shape nobody could defend.

An earlier attempt in the other direction — adding an AI-slop phrase detector and sentence
variance check — was built and reverted the same day. Such rules are not general, go obsolete,
and encode the author's taste as if it were correctness.

# Division of labour

Judgment belongs to editor agents, including a cold reader that receives the finished article
alone with no draft history. Deterministic code catches only what judgment cannot be trusted
to catch — see [model self-assessment](/failure-modes/model-self-assessment.md).

# Consequence

A gate failing does not have to destroy a run. The blog example carries a quality policy:
strict refuses to publish anything missing a gate; best-effort keeps the article and discloses
which gate failed. A terminal gate that discards a finished run is a bug, not strictness.
