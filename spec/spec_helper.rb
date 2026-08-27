# frozen_string_literal: true

require 'stringio'
require 'ruby_llm/team'

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

# Skips a :live example unless the provider key is present, so the suite
# runs green without API credentials.
def skip_without_key(key)
  skip "Set #{key} to run live specs" unless ENV[key]
end
