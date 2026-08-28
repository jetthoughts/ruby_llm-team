# frozen_string_literal: true

require 'stringio'
require 'ruby_llm/team'

require 'vcr'
require 'webmock/rspec'
require_relative 'support/vcr_configuration'

RubyLLM.configure do |config|
  config.openrouter_api_key = ENV.fetch('OPENROUTER_API_KEY', 'test')
  config.openai_api_key = ENV.fetch('OPENAI_API_KEY', 'test')
  config.max_retries = 0
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

def skip_without_key(key)
  skip "Set #{key} to run live specs" unless ENV[key]
end

def skip_without_cassette_or_key(key)
  cassette = RSpec.current_example.metadata[:vcr]
  cassette_path = File.join('spec/fixtures/vcr_cassettes', "#{cassette}.yml") if cassette
  return if cassette_path && File.file?(cassette_path)

  skip_without_key(key)
end
