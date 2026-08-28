# frozen_string_literal: true

module RubyLLM
  class Team
    # Imperative convenience wrapper around one Team::Session.
    class Run
      OUTPUT_UNSET = Object.new.freeze
      private_constant :OUTPUT_UNSET

      attr_reader :session

      def initialize(session)
        @session = session
      end

      # Omitting +from:+ hands over the latest version of every completed
      # artifact, matching Session#ask; pass +from: []+ to start clean.
      def step(name, with:, prompt: nil, from: nil)
        session.ask(with, prompt || "Complete '#{name}'.", as: name, from: from)
      end

      def output(name = OUTPUT_UNSET)
        return selected_output if name.equal?(OUTPUT_UNSET)

        name = name.to_s
        raise ArgumentError, "No completed artifact named '#{name}'" unless artifact(name)

        @output_name = name
        self
      end

      def value(name) = session.value(name)
      def artifact(name) = session.artifact(name)
      def artifacts(name) = session.artifacts(name)
      def calls = session.calls
      def calls_remaining = session.calls_remaining
      def to_markdown = session.to_markdown
      def to_h(include_content: false) = session.to_h(include_content: include_content)

      # Mirrors Session#to_json, positional generator state included, so JSON.generate(run)
      # works the same way.
      def to_json(*args, include_content: false) = session.to_json(*args, include_content: include_content)

      private

      def selected_output
        return unless @output_name

        value(@output_name)
      end
    end
  end
end
