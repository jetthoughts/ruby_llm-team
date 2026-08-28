# frozen_string_literal: true

require 'spec_helper'
require_relative '../../examples/editorial_pipeline'

# Stands in for the lead model choosing from the shortlist.
class FakeChooser
  attr_reader :content

  def initialize(verdict, consult: nil)
    @verdict = verdict
    @consult = consult
  end

  def with_tools(*tools)
    @ask = tools.last
    self
  end

  def with_instructions(_text) = self

  def ask(_shortlist)
    @ask.call('coworker' => @consult.to_s, 'question' => 'Does your lens change this?') if @consult
    @content = @verdict
    self
  end
end

RSpec.describe EditorialPipeline do
  let(:recommendation) do
    {
      'title' => 'Writing Idiomatic Ruby with LLMs',
      'reader_pain' => 'models emit Python-shaped Ruby',
      'angle' => 'prompt and post-process for community conventions',
      'evidence_urls' => ['https://example.com/why-llms-struggle-with-ruby']
    }
  end

  let(:shortlist) do
    { 'recommendations' => [
      { 'title' => 'Ranked first', 'reader_pain' => 'a', 'angle' => 'x' },
      { 'title' => 'Ranked second', 'reader_pain' => 'b', 'angle' => 'y' }
    ] }
  end

  def analyst_team
    signal = Class.new { def ask(_prompt) = { 'signals' => [] } }
    TopicAnalyst::LENSES.each_key.reduce(RubyLLM::Team.new) { |team, lens| team.add(lens, signal) }
  end

  it 'lets the panel overrule the ranking, and records whom it consulted' do
    chooser = FakeChooser.new('PICK: Ranked second — better gap.', consult: :coverage)

    choice, session = described_class.choose(shortlist, chat: chooser, team: analyst_team)

    expect(choice.fetch('title')).to eq('Ranked second')
    expect(session.calls.map(&:coworker)).to eq(['coverage'])
  end

  it 'keeps the ranking when the panel names nothing recognisable' do
    chooser = FakeChooser.new('I cannot decide.')

    choice, = described_class.choose(shortlist, chat: chooser, team: analyst_team)

    expect(choice.fetch('title')).to eq('Ranked first')
  end

  it 'does not convene a panel when there is nothing to argue about' do
    single = { 'recommendations' => [{ 'title' => 'Only option' }] }

    choice, session = described_class.choose(single, team: analyst_team)

    expect(choice.fetch('title')).to eq('Only option')
    expect(session).to be_nil
  end

  it 'turns an analyst recommendation into a blog brief that keeps the shared voice policy' do
    brief = described_class.brief_for(recommendation)

    expect(brief).to include(
      'Writing Idiomatic Ruby with LLMs',
      'models emit Python-shaped Ruby',
      'prompt and post-process for community conventions',
      'https://example.com/why-llms-struggle-with-ruby'
    )
    expect(brief).to include('Voice ledger:', 'Online research policy:')
    # The voice gate scores authenticity, so the brief must say what the author may claim.
    expect(brief).to include('Author basis:', 'not from personal history')
  end

  it 'drives the blog team with the recommendation instead of the retry defaults' do
    workflow = described_class.blog_workflow_for(recommendation, on_step: nil)

    expect(workflow.session).to be_a(RubyLLM::Team::Session)
    expect(workflow.session.to_markdown).to include('Writing Idiomatic Ruby with LLMs')
    expect(workflow.session.to_markdown).not_to include('retries are bounded traffic control')
  end

  it 'keeps a pipeline draft when a gate fails, and discloses the failure' do
    workflow = described_class.blog_workflow_for(recommendation, on_step: nil)
    allow(workflow).to receive(:run) do
      workflow.send(:fail_gate!, :voice_editor)
      'the article'
    end

    expect(described_class.article_with_warnings(workflow))
      .to include('the article', '## Quality warnings', 'voice_editor did not pass its quality gate')
  end

  it 'still refuses to publish a strict run that misses a gate' do
    strict = BlogWorkflow.new(on_step: nil)

    expect { strict.send(:fail_gate!, :voice_editor) }.to raise_error(
      BlogWorkflowError, 'voice_editor did not pass its quality gate'
    )
  end

  it 'drops the retry-specific publication requirements for a new topic' do
    expect(described_class.contract_for.required_text).to be_empty
    expect(PUBLICATION_CONTRACT.required_text).to include('RubyLLM.configure')
  end

  it 'researches the open web for an analyst topic instead of the retry-article plan' do
    plan = described_class.research_for(recommendation)

    expect(plan.query).to eq('Writing Idiomatic Ruby with LLMs')
    expect(plan.domains).to be_nil
    expect(plan.highlight_filter).to be_nil
    expect(RESEARCH_PLAN.domains).to eq(['rubyllm.com'])
  end
end
