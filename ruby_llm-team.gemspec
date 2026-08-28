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
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Ship only tracked library files; examples, docs, traces, and any local scratch
  # files under lib/ stay out of the package.
  spec.files = Dir.chdir(__dir__) do
    tracked = `git ls-files -z`.split("\x0")
    files = tracked.grep(%r{^lib/.*\.rb$}) + (tracked & %w[README.md CHANGELOG.md LICENSE.txt])
    # Outside a git checkout `git ls-files` returns nothing and this would build an empty,
    # unloadable gem. A published version number can never be replaced, so fail loudly.
    raise 'gem must be built from a git checkout; `git ls-files` returned no files' if files.empty?

    files
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby_llm', '>= 1.16.0'
end
