# frozen_string_literal: true

require 'ruby_llm'
require 'ruby_llm/tool'
require 'ruby_llm/team/version'
require 'ruby_llm/team/artifact'
require 'json'
require 'securerandom'

module RubyLLM
  # Groups named coworkers and creates tools for delegating work.
  #
  #   team = RubyLLM::Team.new
  #   team.add(:researcher, ResearcherAgent)
  #
  #   session = team.session(max_calls: 8)     # bound what the model may spend
  #   chat.with_tools(*session.tools)
  #
  # The session keeps the artifacts, budget, and trace reachable after the model is done.
  #
  # Registered classes are instantiated per call; registered instances are reused.
  class Team
    class CollaborationError < StandardError; end
    # Raised when the session's +max_calls+ budget rejects a call.
    class BudgetExceededError < CollaborationError; end
    require 'ruby_llm/team/run'

    # Every call costs money, so a run is bounded unless you say otherwise. This is a smoke
    # alarm rather than a budget: it stops a runaway, and a workflow that legitimately needs
    # more says so in one keyword — examples/blog/workflow.rb passes 40. Pass
    # +max_calls: nil+ for an unbounded run.
    DEFAULT_MAX_CALLS = 25

    def initialize
      @agents = {}
    end

    # Registers +agent+ under +role+ and returns +self+.
    def add(role, agent)
      role = role.to_s
      raise ArgumentError, 'provide a role' if role.empty?
      raise ArgumentError, 'provide an agent' unless agent

      @agents[role] = agent
      self
    end

    # Creates isolated collaboration state for one lead-agent run.
    def session(max_calls: DEFAULT_MAX_CALLS, share_context: true, context: nil)
      Session.new(@agents.dup.freeze, max_calls: max_calls, share_context: share_context, context: context)
    end

    # Executes an ordinary Ruby workflow over one isolated session.
    def run(max_calls: DEFAULT_MAX_CALLS, share_context: true, context: nil)
      execution = Run.new(session(max_calls: max_calls, share_context: share_context, context: context))
      yield execution if block_given?
      execution
    end

    # Preserves coworker results, limits calls, and exposes a trace for one run.
    class Session # rubocop:disable Metrics/ClassLength
      Call = Struct.new(:action, :coworker, :prompt, :result, :status, :inputs, :artifact, :usage,
                        keyword_init: true) do
        def error? = result.is_a?(Hash) && (result.key?(:error) || result.key?('error'))
        def complete? = status != :running
        def successful? = complete? && !error?
      end

      BUDGET_MESSAGE = 'Collaboration call limit reached'
      private_constant :BUDGET_MESSAGE

      def initialize(agents, max_calls:, share_context:, context:)
        validate_max_calls(max_calls)

        @agents = agents
        @max_calls = max_calls
        @share_context = share_context
        @context = context&.to_s&.dup&.freeze
        @calls = []
        @accepted_calls = 0
        @mutex = Mutex.new
        initialize_run_state
        initialize_agent_mutexes(agents)
      end

      def collaboration_tools
        [DelegateWork.new(self), AskQuestion.new(self)]
      end
      alias tools collaboration_tools

      def ask(coworker, prompt, as: nil, from: nil)
        result = consult(
          action: 'delegate_work', prompt: prompt, coworker: coworker, as: as, from: from
        )
        raise_on_error(result)
      end

      def parallel(tasks, concurrency: :threads, from: nil)
        runner = parallel_runner(concurrency)
        reject_duplicate_roles(tasks)
        work = reserve_batch(tasks, from)
        send(runner, work).transform_values { |result| raise_on_error(result) }
      end

      def calls = @mutex.synchronize { @calls.dup.freeze }

      # Calls still allowed by the budget, or +nil+ when the session is unbounded.
      # Lets an application decide whether an optional pass still fits.
      def calls_remaining
        @mutex.synchronize { @max_calls && [@max_calls - @accepted_calls, 0].max }
      end

      def artifact(name)
        @mutex.synchronize { @artifacts.fetch(name.to_s, []).last }
      end

      def artifacts(name)
        @mutex.synchronize { @artifacts.fetch(name.to_s, []).dup.freeze }
      end

      def value(name) = artifact(name)&.value

      def to_markdown
        trace = calls.map.with_index(1) do |call, index|
          result = call.complete? ? format_result(call.result) : '_In progress_'
          inputs = call.inputs.empty? ? '_None_' : call.inputs.join(', ')
          # The whole prompt, handoffs included: "what was actually sent" is the point of
          # the trace, so the readable format must not be the one that hides it.
          "## #{index}. #{call.coworker} via #{call.action}\n\n" \
            "### Inputs\n\n#{inputs}\n\n### Request\n\n#{call.prompt}\n\n" \
            "### Result\n\n#{result}"
        end.join("\n\n")
        @context ? "## Shared team context\n\n#{@context}\n\n#{trace}" : trace
      end

      # Machine-readable trace: structure and best-known usage by default;
      # pass +include_content: true+ to also export prompts and results.
      def to_h(include_content: false)
        # One snapshot under one lock: calls and artifacts must not disagree.
        @mutex.synchronize do
          {
            calls: @calls.each_with_index.map { |call, index| call_to_h(call, index, include_content) },
            artifacts: artifacts_to_h,
            usage: usage_totals(@calls)
          }
        end
      end

      # Accepts JSON's positional generator state so JSON.generate(session) works.
      def to_json(*_args, include_content: false)
        JSON.generate(to_h(include_content: include_content))
      end

      def coworkers = @agents.keys.join(', ')

      def consult(action:, prompt:, coworker:, as: nil, from: nil)
        role = coworker.to_s
        perform(reserve(action, role, prompt, as: as || role, from: from), coworker)
      end

      private

      def initialize_run_state
        @fence = SecureRandom.hex(4)
        @artifacts = {}
        @artifact_serials = Hash.new(0)
        @reserved_versions = {}
      end

      def initialize_agent_mutexes(agents)
        mutexes = {}
        @agent_mutexes = agents.transform_values { |agent| mutexes[agent.__id__] ||= Mutex.new }
      end

      def raise_on_error(result)
        return result unless result.is_a?(Hash) && (result.key?(:error) || result.key?('error'))

        message = result[:error] || result['error']
        # Flagged by the session, never inferred from the text: a coworker may return an
        # error that quotes the budget message.
        raise BudgetExceededError, message if result[:budget_exceeded]

        raise CollaborationError, message
      end

      def reject_duplicate_roles(tasks)
        roles = tasks.map { |coworker, _prompt| coworker.to_s }
        duplicate = roles.tally.find { |_role, count| count > 1 }&.first
        raise ArgumentError, "duplicate coworker '#{duplicate}' in one parallel batch" if duplicate
      end

      def validate_max_calls(max_calls)
        return if max_calls.nil? || (max_calls.is_a?(Integer) && max_calls.positive?)

        raise ArgumentError, 'max_calls must be a positive integer'
      end

      def perform(reservation, coworker)
        return reservation if reservation.is_a?(Hash)

        index, full_prompt = reservation
        execute_call(index, full_prompt, coworker)
      rescue StandardError => e
        complete(index, error: "Coworker '#{coworker}' failed: #{e.message}")
      rescue Exception => e # rubocop:disable Lint/RescueException -- finalize the call, then propagate
        complete(index, error: "Coworker '#{coworker}' crashed: #{e.class}: #{e.message}")
        raise
      end

      def execute_call(index, full_prompt, coworker)
        role = coworker.to_s
        return complete(index, error: unknown_coworker(coworker)) unless @agents.key?(role)

        result = ask_agent(@agents.fetch(role), role, full_prompt)
        complete(index, result: extract_result(result), usage: usage_from(result))
      end

      # Best-known token accounting; absent metering is reported as nil, never guessed.
      def usage_from(raw)
        return unless raw.respond_to?(:input_tokens)

        usage = { input_tokens: raw.input_tokens, output_tokens: raw.output_tokens }
        usage[:model_id] = raw.model_id if raw.respond_to?(:model_id)
        usage = usage.compact
        usage.empty? ? nil : usage
      end

      def unknown_coworker(coworker)
        "Unknown coworker '#{coworker}'. Available: #{coworkers}"
      end

      def reserve(action, coworker, prompt, as:, from:)
        @mutex.synchronize { reserve_call(action, coworker, prompt, artifact_name: as, artifacts: from) }
      end

      def reserve_batch(tasks, from)
        @mutex.synchronize do
          tasks.map do |coworker, prompt|
            role = coworker.to_s
            [coworker, reserve_call('delegate_work', role, prompt, artifact_name: role, artifacts: from)]
          end
        end
      end

      def reserve_call(action, coworker, prompt, artifact_name:, artifacts:)
        artifact_name = normalize_artifact_name(artifact_name)
        return reject_call(action, coworker, prompt, artifact_name) if call_limit_reached?

        prior_calls, inputs = handoff_context(artifacts)
        @accepted_calls += 1
        full_prompt = with_history(prompt, prior_calls.map(&:last))
        [append_running_call(action, coworker, full_prompt, inputs, artifact_name), full_prompt]
      end

      def append_running_call(action, coworker, full_prompt, inputs, artifact_name)
        index = @calls.length
        @reserved_versions[index] = (@artifact_serials[artifact_name] += 1) if artifact_name
        @calls << build_call(
          action, coworker, full_prompt, nil, status: :running, inputs: inputs, artifact: artifact_name
        )
        index
      end

      # Versions are reserved here in submission order, so +artifact(name)+ stays
      # deterministic when parallel work completes out of order. A failed call
      # leaves a visible gap instead of renumbering published versions.
      def handoff_context(artifact_names)
        return context_calls(artifact_names) if @share_context

        if artifact_names && !Array(artifact_names).empty?
          raise ArgumentError, 'from: requires a session that shares context'
        end

        [[], []]
      end

      def call_limit_reached? = @max_calls && @accepted_calls >= @max_calls

      # Names the budget and the blocked coworker so a hand-counted max_calls
      # is diagnosable from the error alone.
      def reject_call(action, coworker, prompt, artifact_name)
        message = "#{BUDGET_MESSAGE}: #{@accepted_calls} of #{@max_calls} calls used, " \
                  "'#{coworker}' was not run"
        append_call(action, coworker, prompt, error: message, artifact: artifact_name)
          .merge(budget_exceeded: true)
      end

      def context_calls(artifact_names)
        return artifact_context(artifact_names) unless artifact_names.nil?

        selected_artifact_context(@artifacts.values.filter_map(&:last).sort_by(&:call_index))
      end

      def artifact_context(names)
        selected = Array(names).map do |name|
          artifact = @artifacts.fetch(name.to_s, []).last
          raise ArgumentError, "No completed artifact named '#{name}'" unless artifact

          artifact
        end
        selected_artifact_context(selected)
      end

      def selected_artifact_context(selected)
        calls = selected.map { |item| [item.call_index, @calls.fetch(item.call_index)] }
        inputs = selected.map { |item| "#{item.name}@v#{item.version} (#{item.producer})" }
        [calls, inputs]
      end

      def normalize_artifact_name(name)
        return if name.nil?

        value = name.to_s
        raise ArgumentError, 'provide an artifact name' if value.empty?

        value.freeze
      end

      def with_history(prompt, calls)
        full_prompt = @context ? "#{prompt}\n\nShared team context:\n#{@context}" : prompt
        return full_prompt unless @share_context

        history = calls.map { |call| fenced_result(call) }.join("\n\n")
        return full_prompt if history.empty?

        "#{full_prompt}\n\nPrevious coworker results (verbatim):\n#{history}"
      end

      # Each result is wrapped in a per-session random fence. A coworker cannot guess the
      # nonce, so relayed output cannot impersonate a handoff from a coworker that never ran.
      def fenced_result(call)
        "--- result #{@fence} #{call.coworker} via #{call.action} ---\n" \
          "#{format_result(call.result)}\n" \
          "--- end #{@fence} ---"
      end

      # Re-entrancy is a property of the role, not of how it was registered: a class-backed
      # coworker gets a fresh instance per call and so never touches the mutex below.
      def ask_agent(agent, role, prompt)
        if active_roles.include?(role)
          raise CollaborationError, "Coworker '#{role}' cannot be consulted from inside its own call"
        end

        active_roles << role
        begin
          call_agent(agent, role, prompt)
        ensure
          active_roles.delete(role)
        end
      end

      def call_agent(agent, role, prompt)
        return agent.new.ask(prompt) if agent.is_a?(Class)

        @agent_mutexes.fetch(role).synchronize { agent.ask(prompt) }
      end

      # Fiber-local, so concurrent work on the same role stays legal while a nested call
      # inside one fiber or thread is refused.
      def active_roles
        Thread.current[:"ruby_llm_team_active_#{object_id}"] ||= []
      end

      def parallel_runner(concurrency)
        return :parallel_with_threads if concurrency.to_sym == :threads

        if concurrency.to_sym == :fibers
          require 'async'
          return :parallel_with_fibers
        end

        raise ArgumentError, 'concurrency must be :threads or :fibers'
      rescue LoadError
        raise LoadError, "The 'async' gem is required for fiber concurrency"
      end

      def parallel_with_threads(work)
        workers = work.map do |coworker, reservation|
          [coworker, Thread.new { perform(reservation, coworker) }]
        end
        workers.to_h { |coworker, worker| [coworker, worker.value] }
      ensure
        workers&.each { |pair| join_quietly(pair.last) }
      end

      # The first crash already propagates through Thread#value; joining the rest
      # must not mask it with a sibling's exception.
      def join_quietly(worker)
        worker.join
      rescue Exception # rubocop:disable Lint/RescueException
        nil
      end

      def parallel_with_fibers(work)
        Async do |parent|
          workers = work.to_h do |coworker, reservation|
            [coworker, parent.async { crash_as_value(reservation, coworker) }]
          end
          settle_fibers(workers)
        end.wait
      end

      # Async starts tasks eagerly, so a crash escaping the block would abort
      # sibling task creation; carry it as a value and raise after settling.
      def crash_as_value(reservation, coworker)
        perform(reservation, coworker)
      rescue Exception => e # rubocop:disable Lint/RescueException
        e
      end

      # Waits for every task before propagating the first crash, so a sibling
      # is never cancelled with its call still recorded as :running.
      def settle_fibers(workers)
        outcomes = workers.transform_values(&:wait)
        crash = outcomes.each_value.find { |value| value.is_a?(Exception) }
        raise crash if crash

        outcomes
      end

      def complete(index, result: nil, error: nil, usage: nil)
        @mutex.synchronize do
          call = @calls.fetch(index)
          completed, result = completed_call(call, result, error, usage)
          @calls[index] = completed
          publish_artifact(completed, index) if completed.successful? && completed.artifact
          result
        end
      end

      def completed_call(call, result, error, usage)
        result = { error: error } if error
        status = error ? :failed : :completed
        completed = build_call(
          call.action, call.coworker, call.prompt, result,
          status: status, inputs: call.inputs, artifact: call.artifact, usage: usage
        )
        [completed, result]
      end

      def publish_artifact(call, index)
        versions = @artifacts.fetch(call.artifact, [])
        artifact = Artifact.new(
          name: call.artifact,
          version: @reserved_versions.fetch(index),
          producer: call.coworker,
          sources: call.inputs,
          value: call.result,
          call_index: index
        ).freeze
        @artifacts[call.artifact] = [*versions, artifact].sort_by(&:version).freeze
      end

      def append_call(action, coworker, prompt, error:, artifact: nil)
        result = { error: error }
        @calls << build_call(action, coworker, prompt, result, status: :failed, inputs: [], artifact: artifact)
        result
      end

      def build_call(action, coworker, prompt, result, details)
        Call.new(
          action: action,
          coworker: coworker,
          prompt: prompt.to_s.dup.freeze,
          result: immutable(result),
          status: details.fetch(:status),
          inputs: immutable(details.fetch(:inputs)),
          artifact: details.fetch(:artifact),
          usage: immutable(details[:usage])
        ).freeze
      end

      def immutable(value)
        case value
        when Hash then value.to_h { |key, item| [immutable(key), immutable(item)] }.freeze
        when Array then value.map { |item| immutable(item) }.freeze
        when String then value.dup.freeze
        else value
        end
      end

      def call_to_h(call, index, include_content)
        serialized = {
          index: index, action: call.action, coworker: call.coworker,
          status: call.status, artifact: call.artifact, inputs: call.inputs, usage: call.usage
        }
        # The exported prompt is the exact text the coworker received, context and
        # handoffs included — the readable Markdown trace is where it is trimmed.
        serialized.merge!(prompt: call.prompt, result: call.result) if include_content
        serialized
      end

      def usage_totals(snapshot)
        metered = snapshot.filter_map(&:usage)
        return if metered.empty?

        {
          input_tokens: metered.sum { |usage| usage[:input_tokens].to_i },
          output_tokens: metered.sum { |usage| usage[:output_tokens].to_i }
        }
      end

      # Callers hold @mutex.
      def artifacts_to_h
        @artifacts.transform_values do |versions|
          versions.map do |artifact|
            { version: artifact.version, producer: artifact.producer,
              call_index: artifact.call_index, sources: artifact.sources }
          end
        end
      end

      def extract_result(result)
        return result unless result.respond_to?(:content)

        content = result.content
        if content.respond_to?(:text) && content.respond_to?(:attachments)
          attachments = Array(content.attachments)
          content = content.text
        else
          attachments = result.respond_to?(:attachments) ? Array(result.attachments) : []
        end
        attachments.empty? ? content : [content, *attachments]
      end

      def format_result(result)
        result.is_a?(Hash) ? JSON.pretty_generate(result) : result.to_s
      end
    end # rubocop:enable Metrics/ClassLength

    class CoworkerTool < Tool # :nodoc:
      def self.declare_shared_params
        param :coworker, type: 'string', description: 'Name of the coworker to consult'
        param :context, type: 'string', description: 'Shared context for the coworker',
                        required: false
      end

      def initialize(session)
        super()
        @session = session
      end

      def description
        "#{self.class.description}\n\nCoworkers: #{@session.coworkers}"
      end

      private

      def with_context(main, context)
        context ? "#{main}\n\nContext: #{context}" : main
      end

      def consult(action:, prompt:, coworker:)
        @session.consult(action: action, prompt: prompt, coworker: coworker)
      end
    end

    class DelegateWork < CoworkerTool # :nodoc:
      description 'Delegate a task to a coworker and get their result'
      declare_shared_params
      param :task, type: 'string', description: 'The task to delegate'

      def name = 'delegate_work'

      def execute(task:, coworker:, context: nil)
        consult(action: name, prompt: with_context(task, context), coworker: coworker)
      end
    end

    class AskQuestion < CoworkerTool # :nodoc:
      description 'Ask a coworker a question about their expertise'
      declare_shared_params
      param :question, type: 'string', description: 'The question to ask'

      def name = 'ask_question'

      def execute(question:, coworker:, context: nil)
        consult(action: name, prompt: with_context(question, context), coworker: coworker)
      end
    end

    private_constant :CoworkerTool, :DelegateWork, :AskQuestion
  end
end
