# frozen_string_literal: true

# The seven editorial passes, in order, with explicit handoffs between coworkers.
# Read run/ first: every other method is one pass or one bounded quality loop.

require 'timeout'
require 'ruby_llm/team'
require_relative '../support/example_runner'
require_relative 'agents'
require_relative 'brief'

# Runs the seven writing passes with explicit, inspectable handoffs.
class BlogWorkflow # rubocop:disable Metrics/ClassLength
  VOICE_REVISION_LIMIT = 3
  FACT_REVISION_LIMIT = 2
  PUBLICATION_REPAIR_LIMIT = 3
  PASSES = {
    'Research — current evidence' => :research_evidence,
    'Pass 0 — angle selection' => :select_angle,
    'Pass 1 — outline architecture' => :build_outline,
    'Pass 2 — voice-first zero draft' => :write_zero_draft,
    'Pass 3 — argument editing' => :revise_argument,
    'Pass 4 — voice editing' => :revise_voice,
    'Pass 5 — fact and attribution editing' => :revise_facts,
    'Pass 6 — reader value and SEO packaging' => :package_for_readers
  }.freeze
  DEFAULT_AGENTS = {
    cold_reader: ColdReader,
    evidence_researcher: EvidenceResearcher,
    angle_strategist: AngleStrategist,
    outline_architect: OutlineArchitect,
    writer: Writer,
    senior_writer: SeniorWriter,
    argument_editor: ArgumentEditor,
    voice_editor: VoiceEditor,
    fact_editor: FactEditor,
    reader_value_editor: ReaderValueEditor,
    publisher: Publisher,
    ruby_expert: RubyExpert
  }.freeze

  attr_reader :execution, :session, :quality_warnings

  def self.default_team
    DEFAULT_AGENTS.reduce(RubyLLM::Team.new) { |team, (role, agent)| team.add(role, agent) }
  end

  # Each keyword is an independent knob a different article needs to change.
  def initialize(team: self.class.default_team, context: WORKFLOW_CONTEXT, on_step: nil, # rubocop:disable Metrics/ParameterLists
                 research: RESEARCH_PLAN, quality_policy: :strict,
                 validator: BlogPublicationValidator.new(contract: PUBLICATION_CONTRACT))
    @on_step = on_step || ->(_step) {}
    @research = research
    @context = context
    @quality_policy = quality_policy
    @quality_warnings = []
    @validator = validator
    @execution = team.run(max_calls: 40, context: context)
    @session = execution.session
  end

  def run
    PASSES.each { |label, method| invoke_step(label) { send(method) } }
    invoke_step('Final gate — Ruby API validation') { validate_final_post }
    execution.output(:published_post).output.to_s.strip
  end

  private

  def invoke_step(label)
    @on_step.call(label)
    yield
  end

  def research_evidence
    research = execution.step(
      :research, with: :evidence_researcher,
                 prompt: research_prompt
    )
    validate_research!(research)
  end

  def research_prompt
    sources = BlogResearch.search_and_extract(
      query: @research.query, include_domains: @research.domains,
      highlight_filter: @research.highlight_filter
    )
    "Build the evidence report from this fetched source material:\n#{JSON.pretty_generate(sources)}"
  end

  def validate_research!(research)
    findings = research.is_a?(Hash) && (research['findings'] || research[:findings])
    urls = Array(findings).filter_map { |finding| finding['source_url'] || finding[:source_url] }
    return if urls.any? { |url| url.to_s.start_with?('https://') }

    raise BlogWorkflowError, 'Online research returned no HTTPS primary source'
  end

  # Bounded like the editing gates: a "revise" verdict usually means the evidence
  # supports a narrower thesis, which is a correction, not a dead end.
  def select_angle
    first = propose_angle('Pass 0: select and gate the article angle from the current evidence.')
    return if passed?(first)

    # The retry must receive its own rejected angle, or it re-derives the same overclaim.
    require_pass!(:angle_strategist, propose_angle(<<~PROMPT, from: %i[research angle]))
      Pass 0 retry: your previous angle did not pass your own gate. Narrow the thesis to
      exactly what the researched evidence supports, resolve every point in your feedback,
      and return verdict "pass" once the remaining claims are all evidenced.
    PROMPT
  end

  def propose_angle(prompt, from: [:research])
    execution.step(:angle, with: :angle_strategist, from: from, prompt: prompt)
  end

  def build_outline
    outline = execution.step(
      :outline, with: :outline_architect, from: %i[research angle],
                prompt: 'Pass 1: build the outline from the approved angle.'
    )
    sections = outline.is_a?(Hash) && (outline['sections'] || outline[:sections])
    raise BlogWorkflowError, 'Outline has no sections' if Array(sections).empty?
  end

  def write_zero_draft
    execution.step(
      :draft, with: :writer, from: %i[research angle outline],
              prompt: 'Pass 2: write the voice-first zero draft.'
    )
  end

  def revise_argument
    memo = execution.step(
      :argument_review, with: :argument_editor, from: %i[angle outline draft],
                        prompt: 'Pass 3: audit the argument and return the editorial memo.'
    ).to_s
    validate_argument_memo!(memo)
    execution.step(
      :draft, with: :writer, from: %i[outline draft argument_review],
              prompt: 'Revise the full article in the argument editor\'s recommended order.'
    )
  end

  def validate_argument_memo!(memo)
    headings = ['## Keep', '## Cut', '## Missing evidence', '## Logical gaps',
                '## Strongest original insight', '## Skeptical objection', '## Recommended revision order']
    return if headings.all? { |item| memo.include?(item) }

    raise BlogWorkflowError, 'Argument editor returned an incomplete memo'
  end

  def revise_voice
    review = review_voice('Pass 4: score the argument revision against the voice ledger.')
    VOICE_REVISION_LIMIT.times do
      return if voice_passed?(review)

      revise_voice_draft
      review = review_voice('Recheck the voice revision. Enforce the publication gate.')
    end
    return if voice_passed?(review)

    escalate_voice
  end

  def escalate_voice
    execution.step(
      :draft, with: :senior_writer, from: %i[research draft voice_review],
              prompt: 'Escalation: resolve every remaining voice finding in the full article.'
    )
    review = review_voice('Recheck the senior writer escalation against the voice ledger.')
    fail_gate!(:voice_editor) unless voice_passed?(review)
  end

  def revise_voice_draft
    execution.step(
      :draft, with: :writer, from: %i[draft voice_review],
              prompt: 'Return the full article after resolving every voice finding. ' \
                      'Delete unsupported claims; do not defend or replace them.'
    )
  end

  def review_voice(prompt)
    execution.step(:voice_review, with: :voice_editor, from: [:draft], prompt: prompt)
  end

  def voice_passed?(review)
    passed?(review) && score(review, :authenticity) >= 4
  end

  def revise_facts
    review = review_facts('Pass 5: perform the claim-by-claim fact and attribution audit.')
    FACT_REVISION_LIMIT.times do
      return if passed?(review)

      revise_fact_draft
      review = review_facts('Re-audit the factual revision. Pass only supported claims.')
    end
    return if passed?(review)

    escalate_facts
  end

  def revise_fact_draft
    execution.step(
      :draft, with: :writer, from: %i[draft fact_review],
              prompt: 'Revise the full article using the fact audit. Remove unsupported claims.'
    )
  end

  def escalate_facts
    execution.step(
      :draft, with: :senior_writer, from: %i[research draft fact_review],
              prompt: 'Escalation: resolve every remaining fact finding in the full article.'
    )
    review = review_facts('Re-audit the senior writer escalation. Pass only supported claims.')
    require_pass!(:fact_editor, review)
  end

  def review_facts(prompt)
    execution.step(:fact_review, with: :fact_editor, from: %i[research draft], prompt: prompt)
  end

  def package_for_readers
    review_for_readers
    publish_for_readers
    repair_publication
    enforce_reader_gate
    validate_post!(execution.value(:published_post).to_s.strip)
  end

  def review_for_readers
    execution.step(
      :reader_review, with: :reader_value_editor, from: [:draft],
                      prompt: 'Pass 6: review reader value and SEO packaging.'
    )
  end

  def publish_for_readers
    execution.step(
      :published_post, with: :publisher,
                       from: %i[research angle draft voice_review fact_review reader_review],
                       prompt: 'Publish the article using the approved draft and final packaging memo.'
    )
  end

  def repair_publication
    PUBLICATION_REPAIR_LIMIT.times do
      validate_post!(execution.value(:published_post).to_s.strip)
      return
    rescue BlogWorkflowError => e
      execution.step(
        :published_post, with: :publisher, from: [:published_post],
                         prompt: publication_repair_prompt(e)
      )
    end
    validate_post!(execution.value(:published_post).to_s.strip)
  end

  def enforce_reader_gate
    review = review_published_post
    return if passed?(review)

    execution.step(
      :published_post, with: :publisher, from: %i[published_post reader_review],
                       prompt: 'Rework the full article once more using the latest reader-value review.'
    )
    require_pass!(:reader_value_editor, review_published_post)
  end

  def review_published_post
    execution.step(
      :reader_review, with: :reader_value_editor, from: [:published_post],
                      prompt: 'Recheck the published article for reader value.'
    )
  end

  def publication_repair_prompt(error)
    <<~PROMPT
      Return the complete corrected article and resolve every validator finding.
      Delete every code fence except one RubyLLM.configure block. That block may use only
      the five settings in the evidence pack with plain numeric values. Do not name an
      exception or RubyLLM method absent from the evidence pack. Do not mention any
      RubyLLM exception or error class; the evidence pack does not establish one.

      Validator findings (verbatim):
      #{error.message}
    PROMPT
  end

  # Bounded like every other gate: one correction round, then a fresh recheck.
  def validate_final_post
    correct_evidence_compliance unless passed?(review_evidence_compliance)
    # Evidence correction rewrites the article, so it needs the same bounded repair
    # loop the publication pass uses, not one unguarded check.
    repair_publication
    check_citation_provenance
    require_pass!(:cold_reader, read_with_cold_eyes)
  rescue BlogWorkflowError => e
    raise if @quality_policy == :strict

    @quality_warnings << "publication validation failed after repairs: #{e.message.lines.last.to_s.strip}"
  end

  # A stranger's pass over the finished article: it receives the published post only,
  # never the drafts, reviews, or research that made every earlier reviewer sympathetic.
  # Judges the finished article alone: no drafts, reviews, or research history.
  def read_with_cold_eyes
    execution.step(
      :cold_review, with: :cold_reader, from: [:published_post],
                    prompt: 'Read this published article as its intended reader and judge it.'
    )
  end

  # Compares strings instead of asking a model: every link in the article must come from
  # material the workflow fetched or was handed in its brief.
  def check_citation_provenance
    invented = urls_in(execution.value(:published_post)) - (urls_in(@context) + fetched_urls)
    return if invented.empty?

    fail_gate!(:citations, "unfetched sources cited: #{invented.join(', ')}")
  end

  def fetched_urls
    research = execution.value(:research)
    findings = Array(research.is_a?(Hash) && (research['findings'] || research[:findings]))
    findings.filter_map { |finding| finding['source_url'] || finding[:source_url] }
            .map { |url| normalize_url(url) }
  end

  def urls_in(text)
    text.to_s.scan(%r{https?://[^\s)\]<>"']+}).map { |url| normalize_url(url) }.uniq
  end

  def normalize_url(url)
    url.to_s.sub(/[.,;:]+\z/, '').chomp('/').downcase
  end

  def review_evidence_compliance
    execution.step(
      :ruby_review,
      with: :ruby_expert,
      prompt: 'Validate the published article against the evidence pack.',
      from: %i[research published_post]
    )
  end

  def correct_evidence_compliance
    execution.step(
      :published_post, with: :publisher, from: %i[research published_post ruby_review],
                       prompt: evidence_correction_prompt
    )
    require_pass!(:ruby_expert, review_evidence_compliance)
  end

  def evidence_correction_prompt
    <<~PROMPT
      Return the complete corrected article and resolve every Ruby API finding.
      Keep every claim inside the evidence pack: do not name a RubyLLM exception,
      method, or guarantee the pack does not establish, and do not imply retries
      make model output correct.
    PROMPT
  end

  def require_pass!(role, result)
    return if passed?(result)

    fail_gate!(role)
  end

  # A strict run publishes nothing that misses a gate. A best-effort run keeps the
  # article and records what failed, so an exhausted gate costs a warning, not the run.
  def fail_gate!(role, detail = nil)
    message = "#{role} did not pass its quality gate"
    message = "#{message}: #{detail}" if detail
    raise BlogWorkflowError, message if @quality_policy == :strict

    @quality_warnings << message
  end

  def passed?(result)
    verdict(result) == 'pass'
  end

  def verdict(result)
    return unless result.is_a?(Hash)

    result['verdict'] || result[:verdict]
  end

  def score(result, key)
    Integer(result[key.to_s] || result[key])
  rescue ArgumentError, TypeError
    0
  end

  def validate_post!(post)
    @validator.validate!(post)
  end
end # rubocop:enable Metrics/ClassLength

# Executes the example and reports provider failures without a stack trace.
def run_blog_workflow
  workflow = BlogWorkflow.new(on_step: ->(step) { warn "[team] #{step}" })
  ExampleRunner.run(
    label: 'article', output_path: OUTPUT_PATH, trace_path: TRACE_PATH, workflow: workflow,
    rescue_from: [BlogResearch::Error, BlogWorkflowError, Timeout::Error, Faraday::Error]
  ) { workflow.run }
ensure
  BlogResearch.close
end

run_blog_workflow if $PROGRAM_NAME == __FILE__
