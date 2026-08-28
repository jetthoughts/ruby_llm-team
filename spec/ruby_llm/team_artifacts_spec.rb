# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Team artifact versioning' do
  it 'orders artifact versions by submission even when completion order inverts' do
    started = Queue.new
    release = Queue.new
    slow = Class.new do
      define_method(:ask) do |_prompt|
        started << true
        release.pop
        'SLOW RESULT'
      end
    end
    fast = Class.new do
      def ask(_prompt) = 'FAST RESULT'
    end
    session = RubyLLM::Team.new.add(:writer, slow).add(:senior, fast).session

    first = Thread.new { session.ask(:writer, 'zero draft', as: :draft, from: []) }
    started.pop
    session.ask(:senior, 'rescue draft', as: :draft, from: [])
    release << true
    first.join

    expect(session.artifacts(:draft).map { |artifact| [artifact.version, artifact.producer] })
      .to eq([[1, 'writer'], [2, 'senior']])
    expect(session.value(:draft)).to eq('FAST RESULT')
  end

  it 'skips the version a failed call reserved instead of renumbering survivors' do
    attempts = []
    flaky = Class.new do
      define_method(:ask) do |prompt|
        attempts << prompt
        raise 'boom' if attempts.one?

        'RECOVERED'
      end
    end
    session = RubyLLM::Team.new.add(:writer, flaky).session

    expect { session.ask(:writer, 'first', as: :draft, from: []) }
      .to raise_error(RubyLLM::Team::CollaborationError)
    session.ask(:writer, 'retry', as: :draft, from: [])

    expect(session.artifacts(:draft).map(&:version)).to eq([2])
    expect(session.value(:draft)).to eq('RECOVERED')
  end
end
