# frozen_string_literal: true

require 'spec_helper'
require_relative '../../examples/blog/research'

RSpec.describe BlogResearch do
  before do
    described_class.close
  end

  after do
    described_class.close
  end

  it 'connects the shared toolset to the You.com search and extraction profile' do
    search_tool = double('you-search')
    client = double('MCP client', tools: [search_tool], stop: nil)
    expect(RubyLLM::MCP).to receive(:client).with(
      name: 'you-search',
      transport_type: :streamable,
      request_timeout: BlogResearch::TIMEOUT_SECONDS * 1000,
      config: { url: WebResearch::URL, headers: WebResearch.send(:auth_headers) }
    ).and_return(client)

    expect(described_class.tools).to eq([search_tool])
    expect(described_class.tools).to equal(described_class.tools)
  end

  it 'authenticates with YDC_API_KEY so usage counts against the caller, not a shared pool' do
    stub_const('WebResearch::API_KEY', 'ydc-sk-test')

    expect(WebResearch.send(:auth_headers)).to eq('Authorization' => 'Bearer ydc-sk-test')
  end

  it 'falls back to the anonymous profile when no key is configured' do
    stub_const('WebResearch::API_KEY', nil)

    expect(WebResearch.send(:auth_headers)).to be_empty
    expect(WebResearch::ANONYMOUS_URL).to include('profile=free')
  end

  it 'closes the MCP client after a workflow run' do
    client = double('MCP client', tools: [], stop: nil)
    allow(RubyLLM::MCP).to receive(:client).and_return(client)

    described_class.tools
    described_class.close

    expect(client).to have_received(:stop)
  end

  it 'runs one bounded search with page extraction and returns compact source data' do
    response = {
      'results' => {
        'web' => [
          {
            'title' => 'Error Handling',
            'url' => 'https://rubyllm.com/error-handling/',
            'contents' => { 'highlights' => ['Automatic retries cover transient failures.'] }
          }
        ]
      }
    }
    search_tool = double('you-search', name: 'you-search')
    allow(search_tool).to receive(:execute).and_return(JSON.generate(response))
    client = double('MCP client', tools: [search_tool], stop: nil)
    allow(RubyLLM::MCP).to receive(:client).and_return(client)

    result = described_class.search_and_extract(
      query: 'RubyLLM automatic retries', include_domains: ['rubyllm.com']
    )

    expect(search_tool).to have_received(:execute).with(
      query: 'RubyLLM automatic retries',
      count: 3,
      include_domains: ['rubyllm.com'],
      extraction: { extraction_mode: 'highlights' },
      crawl_timeout: 10
    )
    expect(result.first).to include(
      'url' => 'https://rubyllm.com/error-handling/',
      'highlights' => ['Automatic retries cover transient failures.']
    )
  end

  it 'exposes the MCP integration through a small model-friendly tool' do
    allow(described_class).to receive(:search_and_extract).and_return(
      [{ 'url' => 'https://rubyllm.com/error-handling/' }]
    )

    result = SearchAndExtractSources.new.execute(query: 'RubyLLM automatic retries')

    expect(JSON.parse(result).first.fetch('url')).to start_with('https://rubyllm.com/')
    expect(described_class).to have_received(:search_and_extract).with(
      query: 'RubyLLM automatic retries', include_domains: ['rubyllm.com']
    )
  end
end
