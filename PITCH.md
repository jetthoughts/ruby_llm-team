# PITCH: `ruby_llm-team` — the delegation primitive RubyLLM won't ship, as a gem

One sentence: **a `RubyLLM::Team` is the one multi-agent primitive that plain Ruby cannot
express on its own — letting the *model* choose which named coworker to route to at
runtime — and it belongs in a small extension gem, not in RubyLLM core and not inside a
CrewAI-style orchestration framework.**

This document grounds that claim in the rejection of PR #891, the maintainer's stated
philosophy, the CrewAI model and its community pain, and RubyLLM's own issue history.

---

## 1. The seed: why this gem exists

PR [#891](https://github.com/crmne/ruby_llm/pull/891) ("Add RubyLLM::Team for multi-agent
collaboration") was closed by the maintainer. The rejection is the single most important
fact about this gem, because it defines the *correct* scope:

> "This does not belong in the library. The existing Agentic Workflows documentation
> already shows multi-agent sequencing, routing, handoffs, parallel work, and fan-in
> using plain Ruby and the existing Agent and Tool APIs. Those examples are clearer, use
> less code, and do not require adding another abstraction or public API to RubyLLM."
> — [crmne, PR #891 comment](https://github.com/crmne/ruby_llm/pull/891#issuecomment-5435551502)

Read carefully. The maintainer did **not** say the idea is bad. He said:

1. The **workflow patterns** (sequencing, routing, handoffs, parallel, fan-in) are already
   well served by plain Ruby + Agent + Tool. Adding a process engine would be worse.
2. A new abstraction does not belong in **core**.
3. If a concrete capability can't be expressed with existing APIs, open an issue first.

`ruby_llm-team` answers all three. It adds **no process, no scheduler, no graph**. It is a
thin tool-layer. And it is a **gem**, not a core addition — precisely the escape hatch the
maintainer's "does not belong in the library" leaves open.

---

## 2. The two ways, compared

### The RubyLLM way (maintainer's stance, current docs)

Orchestration is **ordinary Ruby**. `Agent` is a configured chat; `Tool` is a capability;
the docs show sequential, routing, handoff, parallel, fan-in, and evaluator-optimizer as
small plain-Ruby classes. Applications own task order, dependencies, persistence, and
resume. `RubyLLM.workflow` only adds instrumentation correlation — it does not take over
execution.

Strengths: total flexibility, nothing hidden, debuggable, idiomatic, durable (the loop is
interruptible and resumable). Weakness: every team re-writes the same delegation boundary
by hand.

### The CrewAI way

`Crew` / `Agent` / `Task` / `Process` abstractions. Agents declare role/goal/backstory;
tasks declare expected output; the crew runs a `sequential` or `hierarchical` process
(hierarchical needs a manager LLM). Simple to explain, fast to prototype.

Strengths: approachable, opinionated, quick demos; CrewAI reports enterprise adoption and
"14x less code" vs graph frameworks. Weakness: a fixed process model that is **not very
flexible** — the exact tradeoff the user named.

### The decisive evidence

CrewAI's own engineering blog, after "2 billion agentic workflows", lands on the **RubyLLM
position**, not the Crew abstraction:

> "Architecture choices compound fast... separating the predictable from the
> unpredictable. Having deterministic workflows handling the structure, and agents
> deployed strategically where judgment actually matters."
>
> "Many engineers regret graph-based architectures... too many abstraction layers stacked
> on top of each other... when something breaks, the engineers dig through multiple
> indirections just to try finding which prompt or tool caused it."
> — [Lessons From 2 Billion Agentic Workflows](https://blog.crewai.com/lessons-from-2-billion-agentic-workflows/)

The community reports the same friction:

- r/crewai: "Overwhelmed with limitations... outdated dependencies, slow performance."
- r/AI_Agents: "it gets fragile and you lose fine-grained control" in production.
- r/LangChain: "LangGraph and CrewAI are overcomplicating agents... So I abandoned these
  libraries, as a bonus dropped the necessity to use Python in production."
- r/AI_Agents "Who's using CrewAI really?": few teams report production use.

**Conclusion: do not ship a CrewAI-style `Crew`/`Task`/`Process` abstraction.** It would
contradict the maintainer's philosophy, the docs, and CrewAI's own hard-won lessons. The
gem's job is the *opposite*: give Ruby developers the one missing low-level primitive and
let them keep orchestration in plain Ruby.

---

## 3. Shared requests and pains (grounding)

These are the signals that a delegation primitive is genuinely wanted, from RubyLLM's own
issue tracker and the broader community:

| Signal | Source | What it says |
|---|---|---|
| Multi-agent is wanted, but not as transport | [#670 A2A protocol](https://github.com/crmne/ruby_llm/issues/670) (declined, `not_planned`) | People want multi-agent; maintainer drew the line at external transport. **Local delegation is the acceptable scope.** |
| Team idea itself | [#891](https://github.com/crmne/ruby_llm/pull/891) | Rejected on process/scope, not on value. The code was correct and fully tested (17 specs, 97.74% coverage). |
| Long-running, resumable work | [#635 "Interrupting the agentic loop"](https://github.com/crmne/ruby_llm/issues/635) (completed) | Real pain: multi-step loops that must pause/resume across deploys. A team that composes with durable agents fits this. |
| The "one more abstraction" fatigue | Maintainer's rejection; CrewAI blog; community threads | Nobody wants another rigid framework. The gem must stay a primitive, not a platform. |
| Ruby landscape gap | langchain.rb (huge/complex), FlowNodes (minimalist) | No Ruby-idiomatic, provider-agnostic multi-agent delegation primitive exists. RubyLLM is the natural host ecosystem. |

The through-line: **Ruby developers want multi-agent capability without sacrificing
control.** CrewAI-style frameworks sell the former and tax the latter. A small gem that
sells the primitive and leaves control alone is the gap.

---

## 4. What the gem is, and is not

### Is

- `RubyLLM::Team` — a named coworker registry.
- Two ordinary `RubyLLM::Tool`s the model calls at runtime: `delegate_work` and
  `ask_question`. The model, not the developer, picks the coworker.
- Recoverable error contract (`{ error: ... }`), shared `context:`, attachment
  round-tripping, class-vs-instance lifecycle, snapshot concurrency safety.
- Composes with the existing RubyLLM way: plain-Ruby workflow classes, durable agents,
  `RubyLLM.workflow` instrumentation.

### Is not

- Not a `Crew`/`Task`/`Process` engine. No sequential/hierarchical process, no scheduler,
  no executor, no graph.
- Not an A2A transport. No host-boundary communication.
- Not a replacement for the Agentic Workflows patterns — those stay in plain Ruby, per the
  maintainer.

The differentiator in one line: **Team is where the model decides; the workflow is where
the developer decides.** CrewAI lets the framework decide both; plain Ruby leaves both to
you; this gem takes only the part the model must own.

---

## 5. The pitch

> RubyLLM gives you one beautiful API for every provider, and says "orchestrate with
> plain Ruby." That's right — until you want the *model* to route work to a named
> specialist at runtime. Today every team hand-rolls that delegation boundary: a registry,
> two tool classes, an error contract, attachment handling. `ruby_llm-team` is that
> boundary, extracted, tested, and composable — so your orchestration stays plain Ruby and
> the model's delegation stays first-class.
>
> - **For RubyLLM users:** one line of setup, two tools, no framework.
> - **For the maintainer's philosophy:** no new abstraction in core, no process engine,
>   no transport — just a Tool boundary that plain Ruby couldn't express.
> - **For the market:** the Ruby gap between "single agent" and "crew" — without the crew's
>   rigidity.

---

## 6. Sources

- Maintainer rejection: https://github.com/crmne/ruby_llm/pull/891#issuecomment-5435551502
- RubyLLM Agentic Workflows docs: `docs/_advanced/agentic-workflows.md` (working tree)
- CrewAI lessons: https://blog.crewai.com/lessons-from-2-billion-agentic-workflows/
- RubyLLM issues: #670 (A2A, declined), #635 (interrupt loop), #891 (Team), #889 (JSON format)
- Community: r/crewai, r/AI_Agents, r/LangChain threads (linked in section 2)
