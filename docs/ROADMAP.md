# `ruby_llm-team` Roadmap

## Product thesis

> Give RubyLLM agents bounded collaboration without introducing a second orchestration framework.

The gem owns collaboration mechanics:

- coworker registration
- model-directed delegation
- result normalization
- bounded review and revision loops
- collaboration-level quality contracts

Applications own workflow policy:

- sequencing
- persistence
- scheduling
- authorization
- concurrency
- human approvals
- business rules
- cross-service communication

The roadmap deliberately borrows the useful production lessons from CrewAI without copying its full `Crew`/`Task`/`Process` abstraction stack.

---

## What the roadmap is based on

The rejected RubyLLM Team contribution was closed for two reasons:

1. New features require an approved issue before implementation.
2. Multi-agent sequencing, routing, handoffs, parallel work, and fan-in already work as plain Ruby using `Agent` and `Tool`.

The maintainer's position is an important design constraint, not a reason to abandon the idea. The extension must remain outside RubyLLM core and must solve a concrete collaboration gap rather than introduce a general workflow engine.

CrewAI's current production guidance is also instructive. It recommends:

- deterministic flows around agent work
- explicit state
- structured outputs
- task guardrails
- human oversight
- tracing and usage visibility
- persistence for long-running work

Those are real production needs. They do not require this gem to own a graph, scheduler, persistence backend, or deployment platform.

---

## The product boundary

```ruby
team.tools
# The model chooses which coworker to consult.

team.review(...)
# The gem runs one explicit, bounded quality loop.

plain Ruby
# The developer chooses the workflow.

RubyLLM
# RubyLLM owns models, chats, tools, providers, persistence, and accounting.
```

The central distinction is:

> **The model decides which specialist to call. The developer decides the workflow.**

---

# Phase 0: Validate the premise

**Goal:** prove that developers need a reusable delegation and quality boundary, not another multi-agent framework.

## Deliverables

- standalone `ruby_llm-team` repository
- clear README and examples
- one compelling delegation use case
- one review/revision use case
- issue templates for use cases and feature requests
- `PITCH.md` explaining the scope and differentiation

## Validation experiments

Lead with user problems, not the word “Team”:

1. “How do I let one RubyLLM agent consult a specialist?”
2. “How do I make an agent revise output after an editor rejects it?”
3. “How do I add a bounded evaluator loop without adopting CrewAI?”
4. “How do I preserve control over a multi-agent workflow in Rails?”

Measure:

- gem installs
- GitHub stars
- README clicks
- examples copied
- issues opened
- requests for features
- production use reports
- users who would otherwise hand-roll the same boundary

## Stop condition

Do not expand the API unless users demonstrate one of the following:

- repeated manual delegation implementations
- repeated manual review/revision loops
- requests for coworker filtering or authorization
- requests for durable review execution
- a production use case with measurable value

---

# Phase 1: Delegation primitive

**Target:** `0.1.0`

The first release should be intentionally small.

## Public API

```ruby
require "ruby_llm/team"

team = RubyLLM::Team.new
team.add(:researcher, ResearcherAgent)
team.add(:writer, WriterAgent)

chat
  .with_tools(*team.tools)
  .ask("Research and write an article about Ruby.")
```

## Include

### Coworker registration

```ruby
team.add(:researcher, ResearcherAgent)
team.add(:support, SupportAgent.new)
```

Support:

- agent classes
- agent instances
- duck-typed objects responding to `ask`
- replacement of duplicate roles
- explicit class-versus-instance lifecycle
- stable registry snapshots

### Model-callable tools

Provide two focused tools:

```text
delegate_work
ask_question
```

Each supports:

- coworker
- task or question
- optional context
- available coworker descriptions
- recoverable errors

### Result normalization

Support:

- strings
- `RubyLLM::Message`
- `RubyLLM::Content`
- attachments
- structured content
- recoverable failures

### Error handling

Unknown roles and coworker failures must return information the orchestrator can act on:

```ruby
{
  error: {
    type: "unknown_coworker",
    coworker: "editor",
    available: ["researcher", "writer"]
  }
}
```

```ruby
{
  error: {
    type: "coworker_failure",
    coworker: "researcher",
    message: "Request timed out"
  }
}
```

The exact shape may remain string-compatible during `0.1.x`, but the long-term contract should be structured and stable.

## Explicitly exclude

- task objects
- process modes
- automatic planning
- hidden context copying
- automatic retries
- hidden concurrency
- persistence
- graph DSL
- YAML/JSON configuration
- remote-agent transport

## Success criteria

- gem installs against a released RubyLLM version
- README examples run unchanged
- unit tests cover all public behavior
- at least three complete examples exist
- at least five external users try it
- at least one use case comes from outside the original implementation

---

# Phase 2: Production delegation polish

**Target:** `0.2.0`, only if Phase 1 produces evidence

This phase borrows production concerns from CrewAI without introducing a platform.

## 2.1 Coworker descriptions and capabilities

```ruby
team.add(
  :researcher,
  ResearcherAgent,
  description: "Finds and verifies technical facts",
  capabilities: %i[research sources fact_checking]
)
```

Use metadata to improve tool descriptions and allow users to understand available specialists.

Do not make metadata an automatic planner.

## 2.2 Role filtering

```ruby
chat.with_tools(
  *team.tools(only: %i[researcher writer])
)
```

Support `only:` and `except:` for:

- authorization boundaries
- public/internal agent separation
- task-specific orchestrators
- reducing model confusion
- limiting access to side-effecting coworkers

Prefer application-owned authorization:

```ruby
roles = current_user.admin? ? team.roles : %i[researcher]
chat.with_tools(*team.tools(only: roles))
```

## 2.3 Public registry inspection

Potential API:

```ruby
team.roles
team.fetch(:researcher)
team.include?(:researcher)
team.delete(:researcher)
```

Add only the methods users actually need. The first release should not expose the internal registry hash.

## 2.4 Instrumentation hooks

Integrate with RubyLLM instrumentation instead of creating another tracing system:

```ruby
team = RubyLLM::Team.new(
  on_delegate: ->(event) { Metrics.record(event) }
)
```

Potential event data:

```ruby
{
  coworker: :researcher,
  operation: :delegate_work,
  duration: 1.24,
  success: true
}
```

## 2.5 Usage visibility

Expose existing RubyLLM accounting where possible:

```ruby
result.total_tokens
result.total_cost
result.calls
```

Do not duplicate provider pricing or token accounting.

## Explicitly exclude

- automatic model selection
- provider-specific behavior
- hidden retries
- hidden concurrency
- custom tracing exporters
- dashboards
- deployment infrastructure

## Success criteria

- users request filtering, metadata, or instrumentation
- the added API remains understandable from the README
- no production policy is silently introduced

---

# Phase 3: Bounded quality loops

**Target:** `0.3.0`, only if repeated user demand validates it

This is the most valuable feature to borrow from CrewAI.

CrewAI supports quality behavior through task guardrails, structured outputs, retry limits, human input, and Flows with loops and conditions. The Ruby version should expose the useful pattern directly without reproducing all those abstractions.

## Problem

A model call completing successfully does not mean its output is acceptable:

```text
writer → editor → writer → editor
```

This pattern applies to:

- editorial content
- code review
- research verification
- support responses
- document extraction
- compliance checks
- structured output repair

## Public API

```ruby
result = team.review(
  draft: initial_draft,
  reviewer: :editor,
  reviser: :writer,
  criteria: <<~CRITERIA,
    The draft must:
    - contain no unsupported claims
    - use a clear structure
    - stay under 800 words
  CRITERIA
  max_rounds: 3
)
```

## Result object

```ruby
result.draft
result.approved?
result.exhausted?
result.rounds
result.feedback
result.history
```

Example:

```ruby
if result.approved?
  publish(result.draft)
else
  request_human_review(result)
end
```

## Evaluator contract

Use RubyLLM's existing structured output support:

```ruby
class EditorAgent < RubyLLM::Agent
  schema do
    string :verdict, enum: %w[pass revise]
    string :feedback
  end

  instructions <<~PROMPT
    Evaluate the draft against the supplied criteria.
    Return pass only when every criterion is satisfied.
    Otherwise return revise with actionable feedback.
  PROMPT
end
```

The loop should:

1. ask the reviewer to evaluate the current draft
2. validate the structured verdict
3. return when approved
4. ask the reviser to improve the draft when rejected
5. stop at `max_rounds`
6. return the latest draft and full history when exhausted

## Include

- hard round limit
- structured verdict
- feedback propagation
- explicit approved/exhausted status
- complete round history
- evaluator failure handling
- optional per-round callback
- compatibility with existing Agent schemas

## Explicitly exclude

- infinite loops
- free-form verdict parsing
- automatic “best draft” selection
- hidden retry behavior
- automatic model switching
- editor-specific domain terminology in the core implementation
- a new schema DSL

## Success criteria

- users replace repeated hand-written evaluator loops
- at least two real use cases exist beyond editorial content
- users can estimate cost and latency
- history is useful for debugging and human review

---

# Phase 4: Durable review execution

**Target:** `0.4.0`, only if users need it

Add durability only when review loops must survive:

- process restarts
- deploys
- long-running jobs
- human approval between rounds
- ephemeral workers

## API direction

```ruby
review = team.review_loop(
  draft: draft,
  reviewer: :editor,
  reviser: :writer,
  max_rounds: 3
)

review.step
review.pending?
review.complete?
review.approved?
```

Or serialize a review state:

```ruby
payload = review.to_h
restored = RubyLLM::Team::ReviewLoop.from_h(payload)
```

## Design constraints

Compose with existing RubyLLM capabilities:

- `Chat#step`
- `Chat#complete`
- Rails-backed chats
- ActiveJob
- `RubyLLM.workflow`
- existing instrumentation

## Explicitly exclude

- Team-owned database tables
- ORM dependency
- job queues
- schedulers
- distributed locks
- custom recovery infrastructure

If this phase grows into general workflow persistence, it should become a separate `ruby_llm-workflows` gem rather than expanding Team indefinitely.

---

# Phase 5: Safety and policy boundaries

**Target:** `0.5.0`, driven by production evidence

Potential features:

- per-coworker authorization
- delegation budgets
- side-effect approval boundaries
- timeout integration
- explicit retry policies
- sensitive-context filtering

These features are dangerous to add prematurely because they overlap with:

- RubyLLM provider retry middleware
- job retries
- HTTP timeouts
- tool approval APIs
- application authorization
- cost controls

The default should remain explicit application code:

```ruby
allowed_roles = policy.allowed_coworkers(current_user)
chat.with_tools(*team.tools(only: allowed_roles))
```

Do not add a policy engine until multiple applications need the same behavior.

---

# Phase 6: Optional ecosystem integrations

**Target:** after the core API stabilizes

Possible additions:

- Rails examples
- ActiveJob examples
- Rails instrumentation integration
- Sidekiq guidance
- generators
- example applications
- adapters for existing Ruby agent libraries

The core gem remains plain Ruby and must not depend on Rails.

---

# Explicit non-roadmap

These are deliberately excluded unless the product thesis changes:

- CrewAI-compatible `Crew`
- `Task` domain model
- `Process` abstraction
- graph DSL
- automatic manager agent
- automatic planning
- hidden orchestration
- built-in memory
- built-in RAG
- YAML or JSON project configuration
- A2A or remote-agent transport
- deployment platform
- dashboards
- enterprise authentication
- provider-specific model routing
- hidden caching
- hidden context propagation
- automatic parallelism

---

# Decision gates

Before adding a feature, require all five answers to be satisfactory:

1. Is it requested by multiple real users?
2. Is it difficult to express with ordinary Ruby and RubyLLM?
3. Does it preserve developer ownership of workflow and state?
4. Can it avoid provider-specific behavior?
5. Does it keep the basic delegation example simple?

If any answer is no, keep the capability in documentation or an application-level example instead of adding it to the gem.

---

# Roadmap summary

| Version | Focus | Include | Avoid |
|---|---|---|---|
| `0.1` | Delegation | registry, tools, errors, result normalization | workflow engine |
| `0.2` | Production polish | metadata, filtering, hooks, usage visibility | hidden policy |
| `0.3` | Quality loops | bounded review/revise, structured verdicts, history | infinite ping-pong |
| `0.4` | Durability | explicit stepping/resume if demanded | custom persistence |
| `0.5` | Safety | authorization/budgets if demanded | enterprise platform |
| Later | Integrations | Rails/jobs/examples | A2A, graphs, YAML projects |

## Product promise

> The smallest useful abstraction between one RubyLLM agent and many specialists.

`ruby_llm-team` should not be Ruby's CrewAI. It should provide the collaboration primitive that is repetitive enough to share and narrow enough to keep RubyLLM's control-first philosophy intact.
