# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Team trace serialization' do
  def metered_writer
    Class.new do
      def ask(_prompt)
        RubyLLM::Message.new(
          role: :assistant, content: 'draft one',
          input_tokens: 12, output_tokens: 34, model_id: 'test-model'
        )
      end
    end
  end

  def session_after_run(agent = metered_writer)
    session = RubyLLM::Team.new.add(:writer, agent).session
    session.ask(:writer, 'write', as: :draft, from: [])
    session
  end

  it 'serializes structure and best-known usage without content by default' do
    trace = session_after_run.to_h

    call = trace.fetch(:calls).first
    expect(call).to include(
      index: 0, action: 'delegate_work', coworker: 'writer',
      status: :completed, artifact: 'draft', inputs: [],
      usage: { input_tokens: 12, output_tokens: 34, model_id: 'test-model' }
    )
    expect(call).not_to have_key(:prompt)
    expect(call).not_to have_key(:result)
    expect(trace.fetch(:artifacts)).to eq(
      'draft' => [{ version: 1, producer: 'writer', call_index: 0, sources: [] }]
    )
  end

  it 'includes prompts and results only when content is requested' do
    trace = session_after_run.to_h(include_content: true)

    expect(trace.fetch(:calls).first).to include(prompt: 'write', result: 'draft one')
  end

  it 'exports the exact prompt the coworker received, including handed-over context' do
    session = RubyLLM::Team.new.add(:writer, metered_writer).session(context: 'House style: terse.')
    session.ask(:writer, 'first', as: :draft, from: [])
    session.ask(:writer, 'second', as: :draft, from: [:draft])

    prompt = session.to_h(include_content: true).fetch(:calls).last.fetch(:prompt)

    expect(prompt).to include('second', 'House style: terse.', 'draft one')
  end

  it 'survives JSON.generate, which calls to_json positionally' do
    expect(JSON.parse(JSON.generate(session_after_run.to_h)).fetch('calls').length).to eq(1)
    expect { JSON.generate(session_after_run) }.not_to raise_error
  end

  it 'never fabricates usage for plain string replies' do
    trace = session_after_run(Class.new { def ask(_prompt) = 'no metering here' }).to_h

    expect(trace.fetch(:calls).first.fetch(:usage)).to be_nil
    expect(trace.fetch(:usage)).to be_nil
  end

  it 'totals best-known usage across the run' do
    expect(session_after_run.to_h.fetch(:usage)).to eq(input_tokens: 12, output_tokens: 34)
  end

  it 'renders the same trace as JSON' do
    parsed = JSON.parse(session_after_run.to_json)

    expect(parsed.fetch('calls').first).to include('coworker' => 'writer', 'status' => 'completed')
    expect(parsed.fetch('artifacts').fetch('draft').first.fetch('version')).to eq(1)
  end
end
