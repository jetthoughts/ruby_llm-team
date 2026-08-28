# frozen_string_literal: true

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

namespace :eval do
  desc 'Evaluate the saved blog post with deterministic checks and Tribunal judges'
  task :blog do
    require_relative 'examples/blog/eval'

    BlogWorkflowEval.run!
  end
end

task default: :spec
