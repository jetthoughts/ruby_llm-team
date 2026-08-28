# frozen_string_literal: true

require 'ruby_llm/team'
require_relative '../support/example_runner'

# Fan-out/fan-in code review: three specialists review one diff in parallel,
# a synthesizer merges their findings into a single prioritized review.
module CodeReview
  REVIEW_MODEL = ENV.fetch('RUBYLLM_TEAM_REVIEW_MODEL', 'nvidia/nemotron-3-super-120b-a12b:free')
  SAMPLE_DIFF_PATH = File.join(__dir__, 'sample.diff')
  REVIEW_PATH = File.join(__dir__, 'review.md')
  TRACE_PATH = File.join(__dir__, 'trace.md')

  REVIEW_CONTEXT = <<~CONTEXT
    You are reviewing one Ruby diff for a production Rails application.
    Report only findings inside your specialty, cite the exact line, and never
    invent code that is not in the diff. An empty findings list means approval.
  CONTEXT

  # Shared structured output for every specialist reviewer. There is deliberately no
  # verdict field: models report findings, Ruby decides what they mean.
  class ReviewerAgent < RubyLLM::Agent
    schema do
      array :findings do
        string
      end
    end
  end

  # Flags injection, unsafe interpolation, secrets, and unsafe deserialization.
  class SecurityReviewer < ReviewerAgent
    model REVIEW_MODEL, provider: :openrouter, assume_model_exists: true
    instructions 'Review only for security: injection, unsafe interpolation, secrets, unsafe deserialization.'
  end

  # Flags N+1 queries, unbounded loads, and needless allocations.
  class PerformanceReviewer < ReviewerAgent
    model REVIEW_MODEL, provider: :openrouter, assume_model_exists: true
    instructions 'Review only for performance: N+1 queries, unbounded loads, needless allocations.'
  end

  # Flags naming, ActiveRecord API misuse, and readability problems.
  class StyleReviewer < ReviewerAgent
    model REVIEW_MODEL, provider: :openrouter, assume_model_exists: true
    instructions 'Review only for Ruby style and idiom: naming, ActiveRecord API misuse, readability.'
  end

  # Merges the specialist reviews into one prioritized Markdown review.
  class ReviewSynthesizer < RubyLLM::Agent
    model REVIEW_MODEL, provider: :openrouter, assume_model_exists: true
    instructions <<~PROMPT
      Merge the specialist reviews you receive into one Markdown findings list,
      ordered by severity, each with its specialty and line reference. Do not add
      findings of your own and do not state an overall verdict.
    PROMPT
  end

  # Orchestrates one review run over an isolated Team session.
  class Workflow
    def self.build_team
      RubyLLM::Team.new
                   .add(:security, SecurityReviewer)
                   .add(:performance, PerformanceReviewer)
                   .add(:style, StyleReviewer)
                   .add(:synthesizer, ReviewSynthesizer)
    end

    attr_reader :execution

    def initialize(team: self.class.build_team)
      @team = team
    end

    # The execution is captured before any call runs, so a failed run still has a trace.
    def call(diff)
      @execution = @team.run(max_calls: 4, context: REVIEW_CONTEXT)
      @reviews = execution.session.parallel(review_tasks(diff), from: [])
      execution.step :findings, with: :synthesizer, from: %i[security performance style],
                                prompt: 'Merge the specialist findings into one prioritized list.'
      "#{headline}\n\n#{execution.output(:findings).output}"
    end

    # The gate is deterministic Ruby over reported findings, not model self-assessment:
    # a free model will happily write "approve" above the injection it just found.
    def headline
      blocking = @reviews.values.count { |review| Array(review['findings']).any? }
      return '**Verdict:** approve' if blocking.zero?

      "**Verdict:** request changes — #{blocking} of #{@reviews.size} specialists reported findings"
    end

    private

    def review_tasks(diff)
      prompt = "Review this diff within your specialty only:\n\n#{diff}"
      { security: prompt, performance: prompt, style: prompt }
    end
  end
end

# Executes the example against a diff file (default: the bundled sample).
def run_code_review(diff_path = ARGV.first || CodeReview::SAMPLE_DIFF_PATH)
  ExampleRunner.configure
  workflow = CodeReview::Workflow.new
  ExampleRunner.run(
    label: 'review', output_path: CodeReview::REVIEW_PATH,
    trace_path: CodeReview::TRACE_PATH, workflow: workflow
  ) { workflow.call(File.read(diff_path)) }
end

run_code_review if $PROGRAM_NAME == __FILE__
