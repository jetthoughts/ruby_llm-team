# frozen_string_literal: true

require 'spec_helper'
require_relative '../../examples/blog/workflow'

class BlogSpecCoworker
  attr_reader :prompts

  def initialize(*responses)
    @responses = responses
    @prompts = []
  end

  def ask(prompt)
    @prompts << prompt
    @responses.fetch(@prompts.length - 1)
  end
end

RSpec.describe BlogWorkflow, vcr: 'blog_ruby_expert_revision_workflow' do
  before do
    allow(BlogResearch).to receive(:tools).and_return([])
    allow(BlogResearch).to receive(:search_and_extract).and_return(
      [{ 'title' => 'RubyLLM Error Handling', 'url' => research.dig('findings', 0, 'source_url') }]
    )
  end

  let(:research) do
    {
      'findings' => [
        {
          'exact_claim' => 'RubyLLM retries classified transient failures.',
          'source_title' => 'RubyLLM Error Handling',
          'source_url' => 'https://rubyllm.com/error-handling/#automatic-retries',
          'checked_on' => '2026-08-28',
          'support' => 'The official page documents retry classification and configuration.',
          'current' => true
        }
      ],
      'gaps' => []
    }
  end

  let(:angle) do
    {
      'verdict' => 'pass',
      'thesis' => 'Retries are bounded traffic control, not a correctness strategy.',
      'timely_or_useful' => 'Ruby teams need a clear boundary before shipping LLM calls.',
      'contrary_view' => 'Provider retries are enough for most applications.',
      'author_credibility' => 'The repository runs and validates the documented configuration.',
      'candidate_titles' => ['Retries Cannot Validate AI Output', 'Bound RubyLLM Retries', 'Retries Need a Boundary'],
      'feedback' => []
    }
  end
  let(:outline) do
    {
      'sections' => [
        {
          'heading' => 'Retries solve transport failures, not bad output',
          'reader_question' => 'What can a retry actually fix?',
          'claim' => 'A retry is bounded traffic control.',
          'evidence_or_author_experience' => 'Official RubyLLM error-handling documentation.',
          'example' => 'Configure timeout, retry count, backoff, and jitter.',
          'transition' => 'Separate transport recovery from output validation.',
          'optional' => false
        }
      ]
    }
  end
  let(:argument_memo) do
    <<~MEMO
      ## Keep
      Keep the bounded-traffic-control thesis.
      ## Cut
      Cut generic AI praise.
      ## Missing evidence
      Attribute retry behavior to the official source.
      ## Logical gaps
      Separate transport errors from invalid output.
      ## Strongest original insight
      Retries cannot prove correctness.
      ## Skeptical objection
      Built-in retries may be sufficient for a small application.
      ## Recommended revision order
      State the thesis, show configuration, then define the application boundary.
    MEMO
  end
  let(:voice_review) do
    {
      'verdict' => 'revise', 'point_of_view' => 3, 'lexical_fit' => 3, 'rhythm' => 3,
      'structure' => 3, 'specificity' => 2, 'authenticity' => 2, 'restraint' => 2,
      'feedback' => ['Remove hype and unsupported personal texture.']
    }
  end
  let(:voice_pass) do
    {
      'verdict' => 'pass', 'point_of_view' => 5, 'lexical_fit' => 4, 'rhythm' => 4,
      'structure' => 5, 'specificity' => 4, 'authenticity' => 5, 'restraint' => 5,
      'feedback' => ['The revision matches the documented voice.']
    }
  end
  let(:reader_review) do
    {
      'verdict' => 'revise',
      'recommended_title' => 'Retries Cannot Validate AI Output',
      'feedback' => ['Make the title promise and reader action more specific.']
    }
  end
  let(:reader_pass) do
    {
      'verdict' => 'pass',
      'recommended_title' => 'Retries Cannot Validate AI Output',
      'feedback' => ['The published article gives the intended reader a concrete decision.']
    }
  end
  let(:published_post) do
    <<~MARKDOWN.strip
      # RubyLLM Retries Cannot Validate AI Output

      Retries are traffic control, not a correctness strategy. They can recover from a temporary provider failure. They cannot tell you whether a model returned a usable answer. Production Ruby code needs both boundaries, kept separate.

      ## Bound failures at the provider edge

      RubyLLM automatically retries classified transient failures. Its [error-handling documentation](https://rubyllm.com/error-handling/#automatic-retries) lists network timeouts, connection failures, rate limits, and several provider errors. Context-length errors are not retried.

      Configure that policy once where the client enters your application:

      ```ruby
      RubyLLM.configure do |config|
        config.request_timeout = 10
        config.max_retries = 3
        config.retry_interval = 0.5
        config.retry_backoff_factor = 2
        config.retry_interval_randomness = 0.25
      end
      ```

      The timeout limits each request. The retry count bounds total attempts. Backoff increases the delay after repeated failures, while randomness prevents many workers from retrying at the same instant. These controls reduce pressure during an outage, but they also add latency. Keep the budget modest.

      ## Validate output after transport succeeds

      A successful HTTP response may still contain empty, malformed, or irrelevant content. Validate that result against your application contract before business code sees it. Treat a validation failure as data to reject, not automatic evidence that another identical request will help.

      When RubyLLM exhausts its retries, let application code choose the consequence: enqueue later, show a controlled error, or use a suitable fallback. That decision depends on the feature and should stay visible.

      ## Use the boundary to make failures boring

      Configure transient recovery at the provider edge. Validate model output at the domain edge. Test both paths independently. This separation makes retry cost predictable and prevents a transport convenience from masquerading as correctness.
    MARKDOWN
  end

  it 'runs every pass and returns exact fact-editor feedback to the weak writer' do
    skip_without_cassette_or_key('OPENROUTER_API_KEY')
    allow(FactEditor).to receive(:tools).and_return([])
    allow(RubyExpert).to receive(:tools).and_return([])

    writer = BlogSpecCoworker.new(
      'AI IS REVOLUTIONARY! Call FakeAI.reliable! and everything works.',
      'ARGUMENT_REVISION: FakeAI.reliable! solves every failure.',
      '# Voice attempt one\n\nFakeAI.reliable! fixes everything.',
      '# Voice attempt two\n\nThe system is always reliable.',
      '# Voice attempt three\n\n[NEEDS_AUTHOR_INPUT: invent an anecdote].',
      published_post
    )
    unresolved_draft = '# Calm draft\n\nRetries fix every failure. Call FakeAI.reliable! [CITATION_REQUIRED].'
    team = RubyLLM::Team.new
                        .add(:evidence_researcher, BlogSpecCoworker.new(research))
                        .add(:angle_strategist, BlogSpecCoworker.new(angle))
                        .add(:outline_architect, BlogSpecCoworker.new(outline))
                        .add(:writer, writer)
                        .add(:senior_writer, BlogSpecCoworker.new(unresolved_draft))
                        .add(:argument_editor, BlogSpecCoworker.new(argument_memo))
                        .add(:voice_editor, BlogSpecCoworker.new(*([voice_review] * 4), voice_pass))
                        .add(:fact_editor, FactEditor)
                        .add(:reader_value_editor, BlogSpecCoworker.new(reader_review, reader_pass))
                        .add(:publisher, BlogSpecCoworker.new(published_post))
                        .add(:ruby_expert, RubyExpert)
                        .add(:cold_reader, ColdReader)
    steps = []
    workflow = described_class.new(team: team, on_step: ->(step) { steps << step })

    result = workflow.run

    fact_reviews = workflow.session.calls.select { |call| call.coworker == 'fact_editor' }
    fact_revision = workflow.session.calls.select { |call| call.coworker == 'writer' }.last
    publication = workflow.session.calls.find { |call| call.coworker == 'publisher' }
    final_expert = workflow.session.calls.reverse.find { |call| call.coworker == 'ruby_expert' }
    cold_review = workflow.session.calls.last

    expected_roles = %w[
      evidence_researcher angle_strategist outline_architect writer argument_editor writer
      voice_editor writer voice_editor writer voice_editor writer voice_editor senior_writer
      voice_editor fact_editor writer fact_editor reader_value_editor publisher
      reader_value_editor ruby_expert cold_reader
    ]
    expect(workflow.session.calls.map(&:coworker)).to eq(expected_roles)
    expect(steps).to eq([
                          'Research — current evidence',
                          'Pass 0 — angle selection',
                          'Pass 1 — outline architecture',
                          'Pass 2 — voice-first zero draft',
                          'Pass 3 — argument editing',
                          'Pass 4 — voice editing',
                          'Pass 5 — fact and attribution editing',
                          'Pass 6 — reader value and SEO packaging',
                          'Final gate — Ruby API validation'
                        ])
    expect(fact_reviews.first.result.fetch('verdict')).to eq('revise')
    # The whole review payload reaches the writer verbatim, quotes and all. Asserting the
    # rendered artifact rather than chosen phrases keeps this independent of what the live
    # editor happened to say when the cassette was recorded.
    expect(fact_revision.prompt).to include(JSON.pretty_generate(fact_reviews.first.result))
    expect(fact_revision.prompt).to include('FakeAI.reliable!')
    expect(fact_revision.inputs).to eq(['draft@v6 (senior_writer)', 'fact_review@v1 (fact_editor)'])
    expect(fact_reviews.last.result.fetch('verdict')).to eq('pass')
    expect(fact_reviews.last.inputs).to eq(['research@v1 (evidence_researcher)', 'draft@v7 (writer)'])
    expect(fact_reviews.last.prompt).to include(published_post)
    expect(publication.prompt).to include(*reader_review.fetch('feedback'))
    writer_calls = workflow.session.calls.count { |call| call.coworker == 'writer' && call.successful? }
    expect(writer_calls).to eq(6)
    expect(workflow.session.artifacts(:draft).map(&:version)).to eq((1..7).to_a)
    expected_inputs = ['research@v1 (evidence_researcher)', 'published_post@v1 (publisher)']
    expect(final_expert.inputs).to eq(expected_inputs)
    expect(final_expert.prompt).to include(published_post)
    expect(final_expert.result.fetch('verdict')).to eq('pass')
    # The cold reader judges the finished article alone, with no draft history.
    expect(cold_review.coworker).to eq('cold_reader')
    expect(cold_review.inputs).to eq(['published_post@v1 (publisher)'])
    expect(cold_review.result.fetch('verdict')).to eq('pass')
    expect(result).to eq(published_post)
  end

  it 'gives the search tool to evidence roles only, never to writers' do
    researching = [EvidenceResearcher, FactEditor, RubyExpert]
    synthesizing = [
      AngleStrategist, OutlineArchitect, Writer, SeniorWriter, ArgumentEditor,
      VoiceEditor, ReaderValueEditor, Publisher, ColdReader
    ]

    researching.each do |agent|
      expect(agent.new.tools.keys).to include(:search_and_extract_sources)
    end
    # A writer that can search can also truncate its tool call against max_tokens,
    # which fails the whole call with a JSON parse error.
    synthesizing.each do |agent|
      expect(agent.new.tools.keys).not_to include(:search_and_extract_sources)
    end
  end

  it 'rejects an invented nested RubyLLM constant even after an LLM review passes' do
    validator = BlogPublicationValidator.new

    expect do
      validator.validate!('Rescue RubyLLM::Error::MadeUpRetryError.')
    end.to raise_error(
      BlogWorkflowError,
      /Replace or remove unknown installed constant `RubyLLM::Error::MadeUpRetryError`/
    )
  end

  it 'rejects an invented RubyLLM module method' do
    validator = BlogPublicationValidator.new

    expect do
      validator.validate!('Call RubyLLM.generate.')
    end.to raise_error(
      BlogWorkflowError,
      /Replace or remove unknown installed method `RubyLLM.generate`/
    )
  end

  it 'reports every declared publication problem with corrective guidance' do
    contract = BlogPublicationContract.new(
      required_text: ['primary.example/source'],
      markdown: { title: true, sections: true }
    )
    validator = BlogPublicationValidator.new(contract: contract)

    expect do
      validator.validate!('Call RubyLLM.generate and rescue RubyLLM::MadeUpError.')
    end.to raise_error(BlogWorkflowError) { |error|
      expect(error.message).to include(
        'Add a Markdown H1 title.',
        'Add at least one informative Markdown section.',
        'Add required evidence or wording: primary.example/source.',
        'Replace or remove unknown installed constant `RubyLLM::MadeUpError`.',
        'Replace or remove unknown installed method `RubyLLM.generate`.'
      )
    }
  end
end
