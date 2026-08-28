---
type: Reference
title: What this bundle is for
description: Agent-consumable record of the failure modes and decisions behind ruby_llm-team, deliberately not a copy of the human docs.
resource: https://github.com/jetthoughts/ruby_llm-team
tags: [getting-started, orientation]
timestamp: '2026-08-28T00:00:00Z'
---

# Scope

`ruby_llm-team` coordinates several RubyLLM agents through one auditable run. The human-facing
documents are the README, `docs/DECISIONS.md` (boundary, refusals, known weaknesses) and
`docs/ROADMAP.md`. **This bundle does not restate them.**

It holds the thing those documents compress into prose: each reproduced failure mode as a
discrete, linkable concept with the code that proves it. A prior `.okf/` bundle was deleted
during a documentation consolidation precisely because it duplicated `docs/`; this one exists
only for what has no other home.

# How to use it

- Building on the library, or reviewing similar code? Read
  [/failure-modes/](/failure-modes/index.md) first. Each entry states the symptom, why it was
  reachable, the fix, and the generalisation — most generalise beyond Ruby.
- Deciding whether a behaviour is intentional? Check [/decisions/](/decisions/index.md), then
  `docs/DECISIONS.md` for the full boundary.
- Writing about this work? The failure modes carry the evidence a fact-checker needs.

# What is deliberately absent

No performance benchmarks — none were run. No adoption or download figures — the gem is
unpublished at the time of writing. Anything asserted here names a file or a spec.
