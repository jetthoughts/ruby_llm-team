# frozen_string_literal: true

require 'ruby_llm/team'
require_relative '../support/example_runner'

# The other examples orchestrate in Ruby: your code decides who is consulted, in what order.
# Here nobody does. A lead model is handed the team's delegation tools and works out for
# itself which specialists to consult, how often, and when it has heard enough — then makes
# the call. Team's job is to keep that autonomy affordable and inspectable: the budget stops
# a model that will not stop, and the trace records every consultation it chose to make.
module DecisionPanel
  MODEL = ENV.fetch('RUBYLLM_TEAM_PANEL_MODEL', 'nvidia/nemotron-3-super-120b-a12b:free')
  DECISION_PATH = File.join(__dir__, 'decision.md')
  TRACE_PATH = File.join(__dir__, 'trace.md')
  MAX_CALLS = Integer(ENV.fetch('RUBYLLM_TEAM_PANEL_CALLS', '6'))

  PANEL_CONTEXT = <<~CONTEXT
    A Rails team is choosing between options for a production system. Answer only from your
    own specialty, say plainly when something falls outside it, and name the trade-off you
    would accept rather than pretending one does not exist.
  CONTEXT

  LEAD_INSTRUCTIONS = <<~PROMPT
    You chair a technical decision panel. You do not know the answer yourself.

    Consult the specialists with delegate_work and ask_question. Choose who is worth asking
    and stop as soon as you can defend a recommendation — every consultation costs money, and
    you have a small budget. If a tool returns an error, work with what you already have
    rather than retrying it.

    Finish with: the decision, the strongest argument against it, and what would change your
    mind. Name which specialist supports each point.
  PROMPT

  # Each specialist answers from one angle only, so the lead has a reason to consult more
  # than one of them.
  class Specialist < RubyLLM::Agent
    model MODEL, provider: :openrouter, assume_model_exists: true
  end

  # Judges fit with Rails and its conventions.
  class RailsExpert < Specialist
    instructions 'You know Rails and its ecosystem. Judge fit with the framework and its conventions.'
  end

  # Judges operational burden: deploys, failure modes, on-call cost.
  class OpsExpert < Specialist
    instructions 'You run production systems. Judge operational burden: deploys, failure modes, on-call cost.'
  end

  # Judges cost at small scale and how it grows.
  class CostAnalyst < Specialist
    instructions 'You own the infrastructure budget. Judge cost at small scale and how it grows.'
  end

  def self.build_team
    RubyLLM::Team.new
                 .add(:rails, RailsExpert)
                 .add(:ops, OpsExpert)
                 .add(:cost, CostAnalyst)
  end

  # Runs one panel. The session is created first so its trace survives a failed run.
  class Workflow
    attr_reader :execution

    def initialize(team: DecisionPanel.build_team, chat: nil)
      @team = team
      @chat = chat
    end

    def call(question)
      @execution = @team.session(max_calls: MAX_CALLS, context: PANEL_CONTEXT)
      lead(execution).ask(question).content
    end

    private

    def lead(session)
      (@chat || RubyLLM.chat(model: MODEL, provider: :openrouter, assume_model_exists: true))
        .with_tools(*session.tools)
        .with_instructions(LEAD_INSTRUCTIONS)
    end
  end
end

# Executes the panel for one question, e.g. "Solid Queue or Sidekiq for a 3-person team?"
def run_decision_panel(question = ARGV.join(' '))
  abort 'Usage: ruby examples/decision_panel/workflow.rb "your question"' if question.to_s.strip.empty?

  ExampleRunner.configure
  workflow = DecisionPanel::Workflow.new
  ExampleRunner.run(
    label: 'decision', output_path: DecisionPanel::DECISION_PATH,
    trace_path: DecisionPanel::TRACE_PATH, workflow: workflow
  ) { "# #{question}\n\n#{workflow.call(question)}" }
end

run_decision_panel if $PROGRAM_NAME == __FILE__
