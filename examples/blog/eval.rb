# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require 'ruby_llm'

begin
  require 'ruby_llm/tribunal'
rescue LoadError
  abort 'Install ruby_llm-tribunal and use Ruby 3.2 or newer to run blog evals'
end

# Adapts Tribunal's injectable judge interface to an explicit RubyLLM provider.
class TribunalOpenRouter
  def call(model, messages, _options)
    provider, model_name = model.split(':', 2)
    unless model_name
      provider = 'openrouter'
      model_name = model
    end
    content = response_content(provider, model_name, messages)
    match = content.match(/\{[\s\S]*\}/)
    [:ok, JSON.parse(match ? match[0] : content)]
  rescue StandardError => e
    [:error, "#{e.class}: #{e.message}"]
  end

  private

  def response_content(provider, model, messages)
    chat = RubyLLM.chat(model: model, provider: provider.to_sym, assume_model_exists: true)
                  .with_instructions(messages.first.fetch(:content))
    chat.ask(messages.last.fetch(:content)).content.to_s
  end
end

# Evaluates the saved blog artifact against a reference and Tribunal judges.
# rubocop:disable Metrics/ModuleLength
module BlogWorkflowEval
  ROOT = File.expand_path('../..', __dir__)
  POST_PATH = File.join(__dir__, 'output.md')
  REFERENCE_PATH = File.join(__dir__, 'reference.md')
  REPORT_PATH = File.join(__dir__, 'eval.json')
  MODEL = ENV.fetch('RUBYLLM_TEAM_EVAL_MODEL', 'openrouter:openai/gpt-4.1-mini')
  THRESHOLD = Float(ENV.fetch('RUBYLLM_TEAM_EVAL_THRESHOLD', '0.8'))

  module_function

  def run!
    ensure_inputs!
    configure_provider
    configure_tribunal
    test_case = build_test_case
    results = evaluate_fast(test_case)
    results.merge!(evaluate_with_judges(test_case)) if all_passed?(results)
    report = build_report(results)
    write_report(report)
    print_report(report)
    report.fetch(:passed) ? report : abort('Blog evaluation failed')
  end

  def ensure_inputs!
    raise 'Generate the post first: bundle exec ruby examples/blog/workflow.rb' unless File.file?(POST_PATH)
    return if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.2')

    raise 'ruby_llm-tribunal requires Ruby 3.2 or newer'
  end

  def configure_provider
    RubyLLM.configure do |config|
      config.openrouter_api_key = ENV['OPENROUTER_API_KEY']
      config.request_timeout = Integer(ENV.fetch('RUBYLLM_TEAM_EVAL_TIMEOUT', '60'))
      config.max_retries = 2
      config.retry_interval = 0.5
      config.retry_backoff_factor = 2
      config.retry_interval_randomness = 0.25
    end
  end

  def configure_tribunal
    RubyLLM::Tribunal.configure do |config|
      config.default_model = MODEL
      config.default_threshold = THRESHOLD
      config.verbose = false
    end
  end

  def build_test_case
    RubyLLM::Tribunal.test_case(
      input: <<~REQUEST,
        Write a focused 250-350 word practical article for production Ruby developers.
        Defend the thesis that retries are bounded traffic control, not a correctness
        strategy. Explain where RubyLLM retries belong, what they cannot guarantee, and
        what application code should do after retries are exhausted. Use concise,
        direct prose, one concrete configuration example, and close source attribution.
      REQUEST
      actual_output: File.read(POST_PATH),
      context: [File.read(REFERENCE_PATH)]
    )
  end

  FAST_ASSERTIONS = [
    [:contains_all, {
      values: ['RubyLLM.configure', 'request_timeout', 'max_retries', 'rubyllm.com/error-handling']
    }],
    [:not_contains, { values: ['[NEEDS_AUTHOR_INPUT', '[CITATION_REQUIRED]'] }],
    [:word_count, { min: 250, max: 350 }],
    [:regex, { pattern: '^#\\s+.+$' }]
  ].freeze

  def evaluate_fast(test_case)
    RubyLLM::Tribunal.evaluate(test_case, FAST_ASSERTIONS)
  end

  def evaluate_with_judges(test_case)
    raise 'Set OPENROUTER_API_KEY to run Tribunal judges' unless ENV['OPENROUTER_API_KEY']

    options = { model: MODEL, threshold: THRESHOLD, llm: TribunalOpenRouter.new }
    RubyLLM::Tribunal.evaluate(
      test_case,
      [[:relevant, options], [:faithful, options], [:hallucination, options]]
    )
  end

  def all_passed?(results)
    RubyLLM::Tribunal::Assertions.all_passed?(results)
  end

  def build_report(results)
    {
      generated_at: Time.now.utc.iso8601,
      artifact: POST_PATH.delete_prefix("#{ROOT}/"),
      reference: REFERENCE_PATH.delete_prefix("#{ROOT}/"),
      model: MODEL,
      threshold: THRESHOLD,
      passed: all_passed?(results),
      results: format_results(results)
    }
  end

  def format_results(results)
    results.transform_values { |status, details| { status: status, details: details } }
  end

  def write_report(report)
    FileUtils.mkdir_p(File.dirname(REPORT_PATH))
    File.write(REPORT_PATH, "#{JSON.pretty_generate(report)}\n")
  end

  def print_report(report)
    report.fetch(:results).each do |name, result|
      puts format('%<name>-14s %<status>s', name: name, status: result.fetch(:status).to_s.upcase)
      reason = result.fetch(:details).is_a?(Hash) && result.fetch(:details)[:reason]
      puts "  #{reason}" if reason
    end
    puts "Report: #{REPORT_PATH}"
  end
end
# rubocop:enable Metrics/ModuleLength

BlogWorkflowEval.run! if $PROGRAM_NAME == __FILE__
