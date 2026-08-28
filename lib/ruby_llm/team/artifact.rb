# frozen_string_literal: true

module RubyLLM
  class Team
    # One immutable, successful output published by a coworker call.
    Artifact = Struct.new(:name, :version, :producer, :sources, :value, :call_index, keyword_init: true)
  end
end
