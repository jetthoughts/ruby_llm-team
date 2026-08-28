# frozen_string_literal: true

require 'spec_helper'
require_relative '../../examples/topic_analyst/workflow'

RSpec.describe TopicAnalyst::Workflow do
  let(:research) do
    Class.new do
      def self.search(query:)
        [{ 'title' => "source for #{query}", 'url' => 'https://example.com/post' }]
      end
    end
  end

  def analyst(headline)
    Class.new do
      define_method(:ask) do |_prompt|
        { 'signals' => [{ 'headline' => headline, 'evidence_url' => 'https://example.com/post' }] }
      end
    end
  end

  def offline_strategist(strategist_prompts)
    Class.new do
      define_method(:ask) do |prompt|
        strategist_prompts << prompt
        { 'recommendations' => [{ 'title' => 'Bounded retries', 'confidence' => 4 }] }
      end
    end
  end

  def offline_team(strategist_prompts)
    RubyLLM::Team.new
                 .add(:trends, analyst('async jobs are shifting'))
                 .add(:pains, analyst('idempotency keeps biting people'))
                 .add(:coverage, analyst('basic sidekiq setup is saturated'))
                 .add(:strategist, offline_strategist(strategist_prompts))
  end

  it 'researches every lens in parallel and ranks candidates from all of them' do
    strategist_prompts = []
    workflow = described_class.new(team: offline_team(strategist_prompts), research: research)

    plan = workflow.call('Rails background jobs')

    expect(plan.fetch('recommendations').first.fetch('title')).to eq('Bounded retries')
    expect(strategist_prompts.last).to include(
      'async jobs are shifting', 'idempotency keeps biting people', 'basic sidekiq setup is saturated'
    )
    expect(workflow.execution.artifact(:plan).sources)
      .to contain_exactly('trends@v1 (trends)', 'pains@v1 (pains)', 'coverage@v1 (coverage)')
    expect(workflow.execution.calls.length).to eq(4)
  end

  it 'hands each analyst its own fetched source material' do
    workflow = described_class.new(team: offline_team([]), research: research)
    workflow.call('Rails background jobs')

    lens_prompts = TopicAnalyst::LENSES.keys.map { |lens| workflow.execution.artifact(lens).call_index }
                                       .map { |index| workflow.execution.calls.fetch(index).prompt }

    expect(lens_prompts).to all(include('Fetched source material'))
    expect(lens_prompts.map { |prompt| prompt[/source for [^"]+/] }.uniq.length).to eq(3)
  end

  it 'renders a ranked markdown plan' do
    plan = { 'recommendations' => [{ 'title' => 'Bounded retries', 'confidence' => 4,
                                     'reader_pain' => 'jobs retry forever',
                                     'angle' => 'cap and escalate',
                                     'evidence_urls' => ['https://example.com/post'] }] }

    expect(format_plan(plan)).to include(
      '## 1. Bounded retries (confidence 4/5)', 'jobs retry forever', 'https://example.com/post'
    )
  end
end
