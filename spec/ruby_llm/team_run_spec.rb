# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Team::Run do
  def coworker(response, prompts: [])
    Object.new.tap do |agent|
      agent.define_singleton_method(:ask) do |prompt|
        prompts << prompt
        response
      end
    end
  end

  it 'executes named steps immediately and returns the selected artifact' do
    reviewer_prompts = []
    team = RubyLLM::Team.new
                        .add(:planner, coworker('safe plan'))
                        .add(:reviewer, coworker('approved', prompts: reviewer_prompts))

    execution = team.run(max_calls: 2, context: 'Fix the failure.') do |run|
      run.step :plan, with: :planner, prompt: 'Plan the work.'
      run.step :review, with: :reviewer, from: [:plan], prompt: 'Review the plan.'
      run.output :review
    end

    expect(execution.output).to eq('approved')
    expect(execution.value(:plan)).to eq('safe plan')
    expect(execution.artifact(:review).sources).to eq(['plan@v1 (planner)'])
    expect(reviewer_prompts.last).to include('safe plan')
    expect(execution.to_markdown).to include('reviewer via delegate_work')
    expect(execution.to_h.fetch(:calls).map { |call| call.fetch(:artifact) }).to eq(%w[plan review])
  end

  it 'hands every completed artifact to a step that omits from:' do
    reviewer_prompts = []
    team = RubyLLM::Team.new
                        .add(:planner, coworker('safe plan'))
                        .add(:reviewer, coworker('approved', prompts: reviewer_prompts))

    team.run(max_calls: 2) do |run|
      run.step :plan, with: :planner, prompt: 'Plan the work.'
      run.step :review, with: :reviewer, prompt: 'Review the plan.'
    end

    expect(reviewer_prompts.last).to include('safe plan')
  end

  it 'supports an imperative run without a block' do
    execution = RubyLLM::Team.new.add(:writer, coworker('draft')).run

    execution.step :draft, with: :writer
    execution.output :draft

    expect(execution.output).to eq('draft')
    expect(execution.calls.length).to eq(1)
  end

  it 'rejects an output that has not been produced' do
    execution = RubyLLM::Team.new.run

    expect { execution.output(:missing) }.to raise_error(
      ArgumentError, "No completed artifact named 'missing'"
    )
  end
end
