# frozen_string_literal: true

require 'ripper'
require 'ruby_llm'

class BlogWorkflowError < StandardError; end

# Declares publication requirements without assuming what the generated article says.
class BlogPublicationContract
  attr_reader :word_range, :ruby_examples, :required_text

  def initialize(word_range: nil, ruby_examples: nil, required_text: [], markdown: {}, forbid_placeholders: false)
    @word_range = word_range
    @ruby_examples = ruby_examples
    @required_text = Array(required_text).map { |text| text.to_s.dup.freeze }.freeze
    @require_title = markdown.fetch(:title, false)
    @require_sections = markdown.fetch(:sections, false)
    @forbid_placeholders = forbid_placeholders
  end

  def require_title? = @require_title
  def require_sections? = @require_sections
  def forbid_placeholders? = @forbid_placeholders
end

# Checks a generated article against its declared contract and the installed RubyLLM API.
class BlogPublicationValidator
  PLACEHOLDER = /\[(?:NEEDS_AUTHOR_INPUT|CITATION_REQUIRED)[^\]]*\]/

  def initialize(contract: BlogPublicationContract.new)
    @contract = contract
  end

  def validate!(post)
    article = post.to_s
    examples = article.scan(/```ruby\s*\n(.*?)```/m).flatten
    issues = structure_issues(article, examples)
    issues.concat(ruby_reference_issues(article, examples))
    return article if issues.empty?

    raise BlogWorkflowError, "Publication validation failed:\n- #{issues.join("\n- ")}"
  end

  private

  attr_reader :contract

  def structure_issues(article, examples)
    article_issues(article) + placeholder_issues(article) + required_text_issues(article) +
      example_issues(examples) + word_count_issues(article)
  end

  def article_issues(article)
    issues = []
    issues << 'Return a non-empty article.' if article.strip.empty?
    issues << 'Add a Markdown H1 title.' if contract.require_title? && !article.match?(/^#\s+\S/)
    if contract.require_sections? && !article.match?(/^\#{2,6}\s+\S/)
      issues << 'Add at least one informative Markdown section.'
    end
    issues
  end

  def placeholder_issues(article)
    placeholders = article.scan(PLACEHOLDER).uniq
    return [] unless contract.forbid_placeholders? && placeholders.any?

    ["Resolve drafting placeholders: #{placeholders.join(', ')}."]
  end

  def required_text_issues(article)
    contract.required_text.filter_map do |text|
      "Add required evidence or wording: #{text}." unless article.include?(text)
    end
  end

  def example_issues(examples)
    issues = examples.each_with_index.filter_map do |code, index|
      "Fix invalid Ruby syntax in example #{index + 1}." unless Ripper.sexp(code)
    end
    if contract.ruby_examples && examples.length != contract.ruby_examples
      issues << "Include exactly #{contract.ruby_examples} Ruby example(s); found #{examples.length}."
    end
    issues
  end

  def word_count_issues(article)
    return [] unless contract.word_range

    count = article.scan(/\b[[:alnum:]_'-]+\b/).length
    return [] if contract.word_range.cover?(count)

    ["Use #{contract.word_range.begin}-#{contract.word_range.end} words; found #{count}."]
  end

  def ruby_reference_issues(article, examples)
    unknown_constants(article).map { |path| "Replace or remove unknown installed constant `#{path}`." } +
      unknown_module_methods(article).map { |name| "Replace or remove unknown installed method `RubyLLM.#{name}`." } +
      unknown_settings(examples).map { |name| "Replace or remove unknown installed setting `config.#{name}=`." }
  end

  def unknown_constants(article)
    article.scan(/\bRubyLLM(?:::[A-Z]\w*)+/).uniq.reject { |path| valid_constant_path?(path) }
  end

  def unknown_module_methods(article)
    article.scan(/RubyLLM\.([a-z_]\w*[!?]?)/).flatten.uniq.reject { |name| RubyLLM.respond_to?(name) }
  end

  def unknown_settings(examples)
    examples.join("\n").scan(/config\.([a-z_]\w*)\s*=/).flatten.uniq.reject do |name|
      RubyLLM::Configuration.method_defined?("#{name}=")
    end
  end

  def valid_constant_path?(path)
    path.split('::').drop(1).reduce(RubyLLM) do |namespace, name|
      return false unless namespace.is_a?(Module) && namespace.const_defined?(name, false)

      namespace.const_get(name, false)
    end
    true
  rescue NameError, TypeError
    false
  end
end
