# frozen_string_literal: true

require 'spec_helper'
require_relative '../../examples/blog/workflow'

RSpec.describe 'Citation provenance' do
  # Checked by comparing strings, so no model or network call is involved.
  def workflow_with(article:, research:, context: '', quality_policy: :strict)
    workflow = BlogWorkflow.new(context: context, quality_policy: quality_policy, on_step: nil)
    allow(workflow.execution).to receive(:value) do |name|
      name.to_sym == :research ? research : article
    end
    workflow
  end

  let(:research) do
    { 'findings' => [{ 'source_url' => 'https://rubyllm.com/error-handling/' }] }
  end

  it 'accepts links that came from the fetched research' do
    workflow = workflow_with(
      article: 'See [docs](https://rubyllm.com/error-handling/).', research: research
    )

    expect { workflow.send(:check_citation_provenance) }.not_to raise_error
  end

  it 'rejects a plausible link the workflow never fetched' do
    workflow = workflow_with(
      article: 'See [docs](https://rubyllm.com/invented-page/).', research: research
    )

    expect { workflow.send(:check_citation_provenance) }.to raise_error(
      BlogWorkflowError, %r{citations did not pass.*https://rubyllm\.com/invented-page}
    )
  end

  it 'accepts links handed to the workflow in its brief' do
    workflow = workflow_with(
      article: 'See [analysis](https://example.com/why-ruby).', research: research,
      context: 'Analyst evidence: https://example.com/why-ruby'
    )

    expect { workflow.send(:check_citation_provenance) }.not_to raise_error
  end

  it 'ignores trailing punctuation and slashes when matching' do
    workflow = workflow_with(
      article: 'Read https://rubyllm.com/error-handling.', research: research
    )

    expect { workflow.send(:check_citation_provenance) }.not_to raise_error
  end

  it 'records a warning instead of failing a best-effort run' do
    workflow = workflow_with(
      article: 'See https://rubyllm.com/invented-page/.', research: research,
      quality_policy: :best_effort
    )

    workflow.send(:check_citation_provenance)

    expect(workflow.quality_warnings.first).to include('https://rubyllm.com/invented-page')
  end
end
