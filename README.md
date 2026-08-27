# RubyLLM::Team

Team collaboration for [RubyLLM](https://github.com/crmne/ruby_llm): a `RubyLLM::Team` groups named coworkers and creates tools that let a model delegate work to them.

## Installation

Add the gem to your Gemfile:

```ruby
gem 'ruby_llm-team', require: 'ruby_llm/team'
```

RubyLLM 1.16.0 or newer is required.

## What Is a Team?

A `RubyLLM::Team` groups named coworkers and creates tools that let a model delegate work to them. A Team does not define a task graph or run a process. Use ordinary Ruby or an agentic workflow to coordinate the work around it.

```ruby
team = RubyLLM::Team.new
team.add("Researcher", ResearcherAgent)
team.add("Writer", WriterAgent)

chat.with_tools(*team.collaboration_tools)
chat.ask "Write an article about the benefits of tea"
```

## Registering Coworkers

`add` takes a role and an agent. The agent can be a `RubyLLM::Agent` subclass, an instance, or any object that responds to `#ask`. Use descriptive roles so the model knows which coworker to choose.

```ruby
team.add("Researcher", ResearcherAgent)
```

Each call to a registered class creates a fresh coworker. Register an instance to preserve its conversation:

```ruby
team.add("Support specialist", SupportAgent.new)
```

## Collaboration Tools

`collaboration_tools` returns `delegate_work` and `ask_question`. Pass them to `Chat#with_tools`, or declare them on an agent class:

```ruby
team = RubyLLM::Team.new
team.add("Researcher", ResearcherAgent)

Orchestrator = Class.new(RubyLLM::Agent) do
  tools(*team.collaboration_tools)
end
```

Both tools list the available coworker roles in their descriptions:

| Tool | Arguments | Use it to |
|---|---|---|
| `delegate_work` | `task`, `coworker`, optional `context` | Hand a task to a coworker and get its result |
| `ask_question` | `question`, `coworker`, optional `context` | Consult a coworker about its expertise |

The optional `context:` argument adds labeled shared context after the request.

When a coworker replies with attachments, the tool returns `[content, *attachments]`, so coworkers can hand files or images back to the orchestrator.

## Unknown Coworkers

When the model names an unknown coworker, the tool returns an error such as `{ error: "Unknown coworker 'Editor'. Available: Researcher, Writer" }`. The model can then correct the call and continue.

When a coworker raises while answering, the tool turns the failure into an error such as `{ error: "Coworker 'Editor' failed: <message>" }` instead, so the orchestrator can retry or move on.

## Concurrency

Register every coworker before calling `collaboration_tools`. The returned tools capture a stable snapshot of the registry, so concurrent calls only read Team state and need no locks.

Classes create a fresh coworker for every call. Registered instances are reused, including their conversation state. Register a class whenever you enable concurrent tool execution.

## Development

```bash
bundle install
bundle exec rspec
```

The single `:live` example is skipped unless `OPENROUTER_API_KEY` is set.

## License

MIT. See [LICENSE.txt](LICENSE.txt).