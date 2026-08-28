# frozen_string_literal: true

require 'spec_helper'
require_relative '../../examples/code_review/workflow'

RSpec.describe CodeReview::Workflow do
  def specialist(finding)
    Class.new do
      define_method(:ask) do |_prompt|
        { 'findings' => [finding] }
      end
    end
  end

  def offline_synthesizer(synthesizer_prompts)
    Class.new do
      define_method(:ask) do |prompt|
        synthesizer_prompts << prompt
        "## Verdict: request changes\n- merged review"
      end
    end
  end

  def offline_team(synthesizer_prompts)
    RubyLLM::Team.new
                 .add(:security, specialist('SQL injection via customer_name'))
                 .add(:performance, specialist('N+1 across line_items'))
                 .add(:style, specialist('use pluck instead of map'))
                 .add(:synthesizer, offline_synthesizer(synthesizer_prompts))
  end

  it 'fans specialists out in parallel and hands every review to the synthesizer' do
    synthesizer_prompts = []
    workflow = described_class.new(team: offline_team(synthesizer_prompts))

    review = workflow.call(File.read(CodeReview::SAMPLE_DIFF_PATH))

    expect(review).to include('merged review')
    expect(review).to start_with('**Verdict:** request changes — 3 of 3 specialists reported findings')
    expect(synthesizer_prompts.last).to include(
      'SQL injection via customer_name', 'N+1 across line_items', 'use pluck instead of map'
    )
    expect(workflow.execution.calls.map(&:coworker))
      .to contain_exactly('security', 'performance', 'style', 'synthesizer')
    expect(workflow.execution.artifact(:findings).sources)
      .to contain_exactly('security@v1 (security)', 'performance@v1 (performance)', 'style@v1 (style)')
    expect(workflow.execution.to_markdown).to include('synthesizer via delegate_work')
  end

  it 'stays inside the declared call budget' do
    workflow = described_class.new(team: offline_team([]))
    workflow.call('diff')

    expect(workflow.execution.calls.length).to eq(4)
    expect(workflow.execution.calls).to all(be_successful)
  end

  describe 'live review', :live do
    it 'flags the seeded security, performance, and style problems', vcr: 'code_review_workflow' do
      skip_without_cassette_or_key('OPENROUTER_API_KEY')

      workflow = described_class.new
      review = workflow.call(File.read(CodeReview::SAMPLE_DIFF_PATH))

      specialist_reviews = %i[security performance style].map { |role| workflow.execution.value(role) }
      expect(specialist_reviews.flat_map { |result| result['findings'] }.join)
        .to match(/injection|interpolat/i)
      expect(review).to start_with('**Verdict:** request changes')
      expect(workflow.execution.artifact(:findings).sources.length).to eq(3)
    end
  end
end
