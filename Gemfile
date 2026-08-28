# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development, :test do
  gem 'async', require: false
  gem 'rake'
  gem 'rspec', '~> 3.0'
  gem 'rubocop', require: false
  gem 'ruby_llm-mcp', '~> 1.0', require: false
  gem 'vcr'
  gem 'webmock', '~> 3.18'

  gem 'ruby_llm-tribunal', '~> 0.1', require: false if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.2')
end
