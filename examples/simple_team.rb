# frozen_string_literal: true

require 'ruby_llm/team'

# A complete offline example of an explicit two-coworker handoff.
module SimpleTeamExample
  # Produces a small implementation plan.
  class Planner
    def ask(_prompt)
      <<~PLAN.strip
        1. Reproduce the failing test.
        2. Make the smallest relevant change.
        3. Run the focused test, then the full suite.
      PLAN
    end
  end

  # Confirms that Team supplied the planner's completed artifact.
  class Reviewer
    def ask(prompt)
      raise 'planner result was not handed off' unless prompt.include?('Reproduce the failing test')

      'Approved: the plan is bounded and includes verification.'
    end
  end

  module_function

  def run(output: $stdout)
    execution = build_team.run(
      max_calls: 2,
      context: 'Goal: fix one failing test without unrelated refactoring.'
    ) do |workflow|
      workflow.step :plan, with: :planner, prompt: 'Create a short implementation plan.'
      workflow.step :review, with: :reviewer, from: [:plan], prompt: 'Check whether the plan is safe and testable.'
      workflow.output :review
    end

    output.puts execution.value(:plan), execution.output, '', execution.to_markdown
    execution
  end

  def build_team
    RubyLLM::Team.new
                 .add(:planner, Planner)
                 .add(:reviewer, Reviewer)
  end
end

SimpleTeamExample.run if $PROGRAM_NAME == __FILE__
