# frozen_string_literal: true

require 'spec_helper'
require_relative '../../examples/decision_panel/workflow'

# Stands in for a lead model: it decides which coworkers to consult by calling the tools,
# exactly as a real model would, without any orchestration written in the example.
class FakeLead
  attr_reader :content

  def initialize(consultations)
    @consultations = consultations
  end

  def with_tools(*tools)
    @delegate = tools.first
    self
  end

  def with_instructions(_text) = self

  def ask(_question)
    results = @consultations.map do |role|
      @delegate.call('coworker' => role.to_s, 'task' => 'What do you think?')
    end
    @content = "Decision based on: #{results.join(' | ')}"
    self
  end
end

RSpec.describe DecisionPanel::Workflow do
  def specialist(answer)
    Class.new do
      define_method(:ask) { |_prompt| answer }
    end
  end

  def offline_team
    RubyLLM::Team.new
                 .add(:rails, specialist('Solid Queue is the Rails 8 default.'))
                 .add(:ops, specialist('One fewer service to run.'))
                 .add(:cost, specialist('No Redis bill at this size.'))
  end

  def lead_calling(*consultations) = FakeLead.new(consultations)

  it 'lets the lead choose whom to consult, and records every choice it made' do
    chat = lead_calling(:rails, :cost)
    workflow = described_class.new(team: offline_team, chat: chat)

    answer = workflow.call('Solid Queue or Sidekiq?')

    expect(answer).to include('Solid Queue is the Rails 8 default.', 'No Redis bill at this size.')
    # ops was available and simply not consulted — that was the model's call, not the code's.
    expect(workflow.execution.calls.map(&:coworker)).to eq(%w[rails cost])
    expect(workflow.execution.to_markdown).to include('rails via delegate_work')
  end

  it 'hands earlier answers to later consultations so the panel builds on itself' do
    workflow = described_class.new(team: offline_team, chat: lead_calling(:rails, :ops))
    workflow.call('Solid Queue or Sidekiq?')

    expect(workflow.execution.calls.last.prompt).to include('Solid Queue is the Rails 8 default.')
  end

  it 'stops a lead that will not stop, and says so in the tool result' do
    over_budget = Array.new(DecisionPanel::MAX_CALLS + 2) { :rails }
    workflow = described_class.new(team: offline_team, chat: lead_calling(*over_budget))

    answer = workflow.call('Solid Queue or Sidekiq?')

    expect(workflow.execution.calls_remaining).to be_zero
    expect(answer).to include('Collaboration call limit reached')
    # The budget bounds spend without killing the run: the lead can still answer.
    expect(workflow.execution.calls.count(&:successful?)).to eq(DecisionPanel::MAX_CALLS)
  end

  describe 'live panel', :live do
    it 'consults specialists it chose and returns a decision', vcr: 'decision_panel' do
      skip_without_cassette_or_key('OPENROUTER_API_KEY')

      workflow = described_class.new
      decision = workflow.call('Solid Queue or Sidekiq for a 3-person Rails team? Answer in under 150 words.')

      consulted = workflow.execution.calls.map(&:coworker).uniq
      expect(consulted).not_to be_empty
      expect(consulted - %w[rails ops cost]).to be_empty
      expect(decision).to be_a(String)
      expect(workflow.execution.calls).to all(be_complete)
    end
  end
end
