# frozen_string_literal: true

require_relative 'lib/ruby_llm/team/version'

Gem::Specification.new do |spec|
  spec.name          = 'ruby_llm-team'
  spec.version       = RubyLLM::Team::VERSION
  spec.authors       = ['JetThoughts']
  spec.email         = ['team@jetthoughts.com']

  spec.summary       = 'Team collaboration for RubyLLM: delegate work to named coworkers.'
  spec.description   = 'A RubyLLM extension that groups named coworkers and exposes delegation tools ' \
                       'so a model can hand tasks and questions to teammates. Built on the RubyLLM ' \
                       'public API: Tool, Agent, Message, and Attachment.'
  spec.homepage      = 'https://github.com/jetthoughts/ruby_llm-team'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.1.3')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/releases"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby_llm', '>= 1.16.0'
end
