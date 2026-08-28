# frozen_string_literal: true

require 'fileutils'
require 'ruby_llm/team'

# Shared plumbing for running an example from the command line: provider configuration,
# saving the result and the trace, and reporting provider failures without a stack trace.
# This is example scaffolding, not gem API — Team stays out of configuration and file IO.
module ExampleRunner
  module_function

  def configure(timeout: 60, retries: 2)
    RubyLLM.configure do |config|
      config.openrouter_api_key = ENV['OPENROUTER_API_KEY'] if ENV['OPENROUTER_API_KEY']
      config.request_timeout = Integer(ENV.fetch('RUBYLLM_TEAM_REQUEST_TIMEOUT', timeout.to_s))
      config.max_retries = retries
      config.retry_interval = 1
    end
  end

  # Runs the block, saves its output and the workflow's trace, and turns provider and
  # collaboration failures into a one-line abort. +workflow+ must expose +execution+.
  def run(label:, output_path:, trace_path:, workflow:, rescue_from: [])
    result = yield
    save(output_path, result)
    puts result
    warn "Saved #{label} to #{output_path}"
  rescue RubyLLM::Error, RubyLLM::Team::CollaborationError, *rescue_from => e
    abort "[team] #{label} failed: #{e.message}"
  ensure
    save_trace(workflow.execution, label, trace_path)
  end

  def save(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#{content}\n")
  end

  def save_trace(execution, label, path)
    return unless execution && !execution.calls.empty?

    save(path, "# #{label.capitalize} trace\n\n#{execution.to_markdown}")
    warn "Saved collaboration trace to #{path}"
  end
end
