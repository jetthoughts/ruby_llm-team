# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Team do
  def coworker_class(response: 'done')
    Class.new do
      define_method :ask do |prompt|
        RubyLLM::Message.new(role: :assistant, content: "#{response}: #{prompt}")
      end
    end
  end

  describe '#add' do
    it 'returns itself for chaining' do
      team = described_class.new

      expect(team.add(:researcher, coworker_class)).to equal(team)
    end

    it 'requires a role and an agent' do
      team = described_class.new

      expect { team.add('', coworker_class) }.to raise_error(ArgumentError, 'provide a role')
      expect { team.add(:researcher, nil) }.to raise_error(ArgumentError, 'provide an agent')
    end

    it 'replaces a coworker registered under the same role' do
      team = described_class.new
      team.add(:researcher, coworker_class(response: 'first'))
      team.add(:researcher, coworker_class(response: 'second'))

      result = team.session.tools.first.call({ 'task' => 'check', 'coworker' => 'researcher' })

      expect(result).to eq('second: check')
    end

    it 'detaches a string role from its caller' do
      role = +'researcher'
      team = described_class.new.add(role, coworker_class)
      role.replace('writer')

      result = team.session.tools.first.call({ 'task' => 'check', 'coworker' => 'researcher' })

      expect(result).to eq('done: check')
    end
  end

  describe '#session' do
    it 'shares prior coworker results verbatim with later coworkers' do
      prompts = []
      coworker = Class.new do
        define_method(:ask) do |prompt|
          prompts << prompt
          prompts.one? ? 'DRAFT_V1: unsupported API' : 'EDITOR_REVIEW: REVISE remove unsupported API'
        end
      end
      session = described_class.new.add(:writer, coworker).add(:editor, coworker).session
      delegate, ask = session.tools

      delegate.call('coworker' => 'writer', 'task' => 'Draft')
      ask.call('coworker' => 'editor', 'question' => 'Review')

      expect(prompts.last).to include('Previous coworker results (verbatim):',
                                      'writer via delegate_work', 'DRAFT_V1: unsupported API')
      expect(prompts.last).to match(/--- result \h+ writer via delegate_work ---/)
    end

    it 'hands only the latest explicitly selected artifacts to a coworker' do
      prompts = []
      writer = Class.new do
        define_method(:ask) { |prompt| prompt.start_with?('first') ? 'DRAFT_V1' : 'DRAFT_V2' }
      end
      editor = Class.new do
        define_method(:ask) do |prompt|
          prompts << prompt
          'reviewed'
        end
      end
      session = described_class.new.add(:writer, writer).add(:editor, editor).session

      session.ask(:writer, 'first draft', from: [])
      session.ask(:writer, 'second draft', from: [:writer])
      session.ask(:editor, 'review latest', from: [:writer])

      expect(prompts.last).to include('DRAFT_V2')
      expect(prompts.last).not_to include('DRAFT_V1')
      expect(session.calls.last.inputs).to eq(['writer@v2 (writer)'])
    end

    it 'publishes named artifact versions and hands off the selected latest version' do
      prompts = []
      writer = Class.new do
        define_method(:ask) { |prompt| prompt.start_with?('first') ? 'DRAFT_V1' : 'DRAFT_V2' }
      end
      editor = Class.new do
        define_method(:ask) do |prompt|
          prompts << prompt
          'approved'
        end
      end
      session = described_class.new.add(:writer, writer).add(:editor, editor).session

      session.ask(:writer, 'first draft', as: :draft, from: [])
      session.ask(:writer, 'second draft', as: :draft, from: [:draft])
      session.ask(:editor, 'review', as: :review, from: [:draft])

      expect(session.artifacts(:draft).map(&:version)).to eq([1, 2])
      expect(session.artifact(:draft).producer).to eq('writer')
      expect(session.artifact(:draft).sources).to eq(['draft@v1 (writer)'])
      expect(session.value(:draft)).to eq('DRAFT_V2')
      expect(prompts.last).to include('DRAFT_V2')
      expect(prompts.last).not_to include('DRAFT_V1')
      expect(session.calls.last.inputs).to eq(['draft@v2 (writer)'])
      expect(session.value(:draft)).to eq('DRAFT_V2')
    end

    it 'does not publish failed named artifacts' do
      coworker = Class.new do
        def ask(_prompt) = raise('failed')
      end
      session = described_class.new.add(:writer, coworker).session

      expect { session.ask(:writer, 'draft', as: :draft, from: []) }.to raise_error(
        RubyLLM::Team::CollaborationError
      )
      expect(session.artifacts(:draft)).to be_empty
      expect(session.calls.last.artifact).to eq('draft')
    end

    it 'rejects an explicit handoff without a completed artifact' do
      session = described_class.new.add(:writer, coworker_class).session(max_calls: 1)

      expect { session.ask(:writer, 'revise', from: [:editor]) }.to raise_error(
        ArgumentError, "No completed artifact named 'editor'"
      )
      expect(session.calls).to be_empty
    end

    it 'limits expensive coworker calls and records the rejected attempt' do
      coworker = instance_double('Coworker', ask: 'done')
      session = described_class.new.add(:writer, coworker).session(max_calls: 1)
      delegate = session.tools.first

      expect(delegate.call('coworker' => 'writer', 'task' => 'first')).to eq('done')
      expect(delegate.call('coworker' => 'writer', 'task' => 'second')).to eq(
        error: "Collaboration call limit reached: 1 of 1 calls used, 'writer' was not run",
        budget_exceeded: true
      )
      expect(coworker).to have_received(:ask).once
      expect(session.calls.length).to eq(2)
    end

    it 'exposes results, revision counts, and a readable trace' do
      writer = instance_double('Writer', ask: 'first draft')
      session = described_class.new.add(:writer, writer).session
      delegate = session.tools.first

      delegate.call('coworker' => 'writer', 'task' => 'draft')
      delegate.call('coworker' => 'writer', 'task' => 'revise')

      expect(session.value(:writer)).to eq('first draft')
      expect(session.artifacts(:writer).length).to eq(2)
      expect(session.calls.last.inputs).to eq(['writer@v1 (writer)'])
      expect(session.to_markdown).to include(
        'writer via delegate_work', '### Inputs', 'writer@v1 (writer)', '### Request', '### Result'
      )
    end

    it 'requires a positive call limit' do
      team = described_class.new.add(:writer, coworker_class)

      expect { team.session(max_calls: 0) }.to raise_error(ArgumentError, 'max_calls must be a positive integer')
    end

    it 'raises coworker failures for direct orchestration while retaining the trace' do
      coworker = Class.new do
        def ask(_prompt) = raise('timed out')
      end
      session = described_class.new.add(:writer, coworker).session

      expect { session.ask(:writer, 'draft') }.to raise_error(
        RubyLLM::Team::CollaborationError, "Coworker 'writer' failed: timed out"
      )
      expect(session.calls.last).to be_error
    end

    it 'reserves the call budget atomically across threads' do
      count = 0
      count_mutex = Mutex.new
      coworker = Class.new do
        define_method(:ask) do |_prompt|
          count_mutex.synchronize { count += 1 }
          sleep 0.01
          'done'
        end
      end
      session = described_class.new.add(:writer, coworker).session(max_calls: 3)

      results = 10.times.map do
        Thread.new { session.tools.first.call('coworker' => 'writer', 'task' => 'draft') }
      end.map(&:value)

      expect(count).to eq(3)
      expect(results.count { |result| result == 'done' }).to eq(3)
      expect(results.count { |result| result.is_a?(Hash) }).to eq(7)
      expect(session.artifacts(:writer).length).to eq(3)
    end

    it 'fans work out in threads and carries both results into the next call' do
      final_prompt = nil
      final = Class.new do
        define_method(:ask) do |prompt|
          final_prompt = prompt
          'combined'
        end
      end
      session = described_class.new
                               .add(:expert, coworker_class(response: 'technical feedback'))
                               .add(:editor, coworker_class(response: 'voice feedback'))
                               .add(:writer, final)
                               .session

      results = session.parallel({ expert: 'review code', editor: 'review voice' }, concurrency: :threads)
      answer = session.ask(:writer, 'revise')

      expect(results.values).to contain_exactly('technical feedback: review code', 'voice feedback: review voice')
      expect(final_prompt).to include('technical feedback: review code', 'voice feedback: review voice')
      expect(answer).to eq('combined')
    end

    it 'gives parallel reviewers the same explicitly selected draft' do
      session = described_class.new
                               .add(:writer, coworker_class(response: 'draft'))
                               .add(:expert, coworker_class(response: 'technical'))
                               .add(:editor, coworker_class(response: 'voice'))
                               .session
      session.ask(:writer, 'write', from: [])

      session.parallel(
        { expert: 'review code', editor: 'review voice' },
        concurrency: :threads,
        from: [:writer]
      )

      expect(session.calls.last(2).map(&:inputs)).to all(eq(['writer@v1 (writer)']))
      expect(session.calls.last(2).map(&:prompt)).to all(include('draft: write'))
    end

    it 'serializes one coworker instance registered under multiple roles' do
      coworker = Object.new
      coworker.instance_variable_set(:@active, false)
      coworker.define_singleton_method(:ask) do |prompt|
        raise 'concurrent reuse' if @active

        @active = true
        sleep 0.01
        prompt
      ensure
        @active = false
      end
      session = described_class.new.add(:expert, coworker).add(:editor, coworker).session

      results = session.parallel({ expert: 'technical', editor: 'voice' }, concurrency: :threads)

      expect(results).to eq(expert: 'technical', editor: 'voice')
    end

    it 'gives concurrent fibers completed context without leaking partial results' do
      prompts = {}
      reviewer = lambda do |role|
        Class.new do
          define_method(:ask) do |prompt|
            prompts[role] = prompt
            Fiber.yield
            "#{role} feedback"
          end
        end
      end
      session = described_class.new
                               .add(:writer, coworker_class(response: 'bad draft'))
                               .add(:expert, reviewer.call(:expert))
                               .add(:editor, reviewer.call(:editor))
                               .session
      delegate = session.tools.first
      delegate.call('coworker' => 'writer', 'task' => 'draft')
      fibers = %w[expert editor].map do |role|
        Fiber.new { delegate.call('coworker' => role, 'task' => 'review') }
      end

      fibers.each(&:resume)
      fibers.each(&:resume)

      expect(prompts.values).to all(include('bad draft'))
      expect(prompts[:expert]).not_to include('editor feedback')
      expect(prompts[:editor]).not_to include('expert feedback')
      expect(session.value(:expert)).to eq('expert feedback')
      expect(session.value(:editor)).to eq('editor feedback')
    end

    it 'fans work out with the async fiber scheduler' do
      session = described_class.new
                               .add(:expert, coworker_class(response: 'technical'))
                               .add(:editor, coworker_class(response: 'voice'))
                               .session

      results = session.parallel({ expert: 'review', editor: 'review' }, concurrency: :fibers)

      expect(results).to eq(expert: 'technical: review', editor: 'voice: review')
    end
  end

  describe 'delegation tools' do
    def stateful_coworker
      Class.new do
        def initialize
          @log = []
        end

        def ask(prompt)
          @log << prompt
          RubyLLM::Message.new(role: :assistant, content: "#{@log.size}:#{prompt}")
        end
      end
    end

    def team_with(coworker)
      described_class.new.add(:researcher, coworker)
    end

    let(:team) { team_with(stateful_coworker) }
    let(:tools) { team.session.tools }
    let(:delegate_tool) { tools.first }
    let(:ask_tool) { tools.last }

    it 'returns delegation and question tools' do
      expect(team.session.tools.map(&:name)).to eq(%w[delegate_work ask_question])
    end

    it 'lists the available coworker roles in each tool description' do
      team.add(:writer, coworker_class)
      delegate, ask = team.session.tools

      expect(delegate.description).to end_with('Coworkers: researcher, writer')
      expect(ask.description).to end_with('Coworkers: researcher, writer')
    end

    it 'keeps context optional in the argument schemas' do
      expect(delegate_tool.params_schema['required']).to eq(%w[coworker task])
      expect(ask_tool.params_schema['required']).to eq(%w[coworker question])
      expect(delegate_tool.params_schema['properties']).to have_key('context')
    end

    it 'delegates work and asks questions' do
      delegated = delegate_tool.call({ 'task' => 'Summarize X', 'coworker' => 'researcher' })
      answered = ask_tool.call({ 'question' => 'How big is X?', 'coworker' => 'researcher' })

      expect(delegated).to eq('1:Summarize X')
      # The second call sees the first one's result, which is the point of a session.
      expect(answered).to start_with('1:How big is X?')
      expect(answered).to include('1:Summarize X')
    end

    it 'returns plain coworker replies as-is' do
      coworker = Class.new do
        def ask(_prompt) = 'plain reply'
      end

      result = team_with(coworker).session.tools.first.call(
        { 'task' => 'check', 'coworker' => 'researcher' }
      )

      expect(result).to eq('plain reply')
    end

    it 'reads content from replies without attachments' do
      reply = Struct.new(:content).new('content only')
      coworker = Class.new do
        define_method(:ask) { |_prompt| reply }
      end

      result = team_with(coworker).session.tools.first.call(
        { 'task' => 'check', 'coworker' => 'researcher' }
      )

      expect(result).to eq('content only')
    end

    it 'appends shared context to the coworker prompt' do
      prompts = []
      coworker = Class.new do
        define_method(:ask) do |prompt|
          prompts << prompt
          RubyLLM::Message.new(role: :assistant, content: 'ok')
        end
      end

      team_with(coworker).session.tools.first.call(
        { 'task' => 'Summarize X', 'coworker' => 'researcher', 'context' => 'for an intro' }
      )

      expect(prompts).to eq(["Summarize X\n\nContext: for an intro"])
    end

    it 'instantiates registered classes fresh for every delegation' do
      delegate = team_with(stateful_coworker).session.tools.first

      delegate.call({ 'task' => 'first', 'coworker' => 'researcher' })

      expect(delegate.call({ 'task' => 'second', 'coworker' => 'researcher' })).to start_with('1:second')
    end

    it 'reuses a registered instance between delegations' do
      team = described_class.new.add(:writer, stateful_coworker.new)
      delegate = team.session.tools.first

      expect(delegate.call({ 'task' => 'first', 'coworker' => 'writer' })).to eq('1:first')
      expect(delegate.call({ 'task' => 'second', 'coworker' => 'writer' })).to start_with('2:second')
    end

    it 'returns an error that names available coworkers for an unknown role' do
      result = delegate_tool.call({ 'task' => 'Summarize X', 'coworker' => 'nobody' })

      expect(result[:error]).to eq("Unknown coworker 'nobody'. Available: researcher")
    end

    it 'returns a recoverable error when a coworker raises while answering' do
      coworker = Class.new do
        def ask(_prompt)
          raise 'boom'
        end
      end

      result = team_with(coworker).session.tools.first.call(
        { 'task' => 'check', 'coworker' => 'researcher' }
      )

      expect(result).to eq(error: "Coworker 'researcher' failed: boom")
    end

    it 'returns a recoverable error when a registered class cannot be instantiated' do
      coworker = Class.new do
        def initialize(name)
          @name = name
        end

        def ask(_prompt)
          'ok'
        end
      end

      result = team_with(coworker).session.tools.first.call(
        { 'task' => 'check', 'coworker' => 'researcher' }
      )

      expect(result[:error]).to include("Coworker 'researcher' failed:")
    end

    it 'returns message attachments with the reply content' do
      attachment = RubyLLM::Attachment.new(StringIO.new('image bytes'), filename: 'diagram.png')
      coworker = Class.new do
        define_method(:ask) do |_prompt|
          content = RubyLLM::Content.new('See the diagram', [attachment])
          RubyLLM::Message.new(role: :assistant, content: content)
        end
      end

      result = team_with(coworker).session.tools.first.call(
        { 'task' => 'draw', 'coworker' => 'researcher' }
      )

      expect(result).to eq(['See the diagram', attachment])
    end

    it 'uses a stable snapshot of the registered coworkers' do
      tools = team.session.tools
      team.add(:writer, coworker_class)

      result = tools.first.call({ 'task' => 'Draft', 'coworker' => 'writer' })

      expect(tools.first.description).to end_with('Coworkers: researcher')
      expect(result[:error]).to eq("Unknown coworker 'writer'. Available: researcher")
    end
  end

  describe 'live delegation', :live do
    it 'openrouter/nvidia/nemotron-3-super-120b-a12b:free delegates through collaboration tools' do
      skip_without_key('OPENROUTER_API_KEY')

      model_id = 'nvidia/nemotron-3-super-120b-a12b:free'
      provider = :openrouter
      coworker = Class.new(RubyLLM::Agent) do
        model model_id, provider: provider
        instructions 'You are a terse assistant. Answer in one short sentence.'
      end

      team = described_class.new.add(:researcher, coworker)
      chat = RubyLLM.chat(model: model_id, provider: provider)
                    .with_tools(*team.session.tools)
                    .with_instructions(
                      'You must call the delegate_work tool with coworker "researcher" and ' \
                      'task "What is 2 + 2?" before answering. Then report what it says.'
                    )

      response = chat.ask('What is 2 plus 2? Ask your researcher teammate first.')

      delegation = chat.messages.flat_map { |message| message.tool_calls&.values || [] }.find do |tool_call|
        tool_call.name == 'delegate_work' && tool_call.arguments.values.any? { |value| value.to_s.include?('2 + 2') }
      end
      expect(delegation).not_to be_nil

      tool_result = chat.messages.find { |message| message.tool_call_id == delegation.id }
      expect(tool_result).not_to be_nil
      expect(tool_result.content).to include('4')
      expect(response.content).to include('4')
    end
  end
end
