---
type: Decision
title: VCR matches request bodies exactly, minus the fence nonce
description: Cassettes compare bodies byte-for-byte after normalising only the per-session nonce, so a prompt change still invalidates a recording.
resource: https://github.com/jetthoughts/ruby_llm-team/blob/master/spec/support/vcr_configuration.rb
tags: [testing, vcr, determinism]
timestamp: '2026-08-28T00:00:00Z'
status: accepted
---

# Decision

`match_requests_on: %i[method uri fenced_body]`, where `fenced_body` compares bodies exactly
after replacing the per-session random fence introduced by
[the forged-handoff fix](/failure-modes/forged-handoff.md).

# Why not loosen it further

Request bodies embed the accumulated trace, so any prompt change alters them. That is
deliberate: a prompt edit *should* invalidate the recording rather than silently replay
responses to a question that is no longer being asked. Re-record with `VCR_RECORD_MODE=all`
instead of weakening the matcher.

# Cost, stated honestly

Re-recording needs a real API key and real spend, and live model output is not reproducible —
one blog spec assertion had to be rewritten because it depended on what the editor happened to
say when the cassette was recorded. Assert on the *shape* of the handoff (the rendered
artifact reached the writer) rather than on chosen phrases.

# Consequence

CI replays every cassette with no API key via `rake spec:replay`, which is the same command a
developer runs locally.
