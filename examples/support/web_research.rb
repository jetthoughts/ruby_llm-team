# frozen_string_literal: true

require 'ruby_llm/mcp'
require 'json'

# Shared MCP-backed web search for the examples. Team stays independent of search vendors;
# each example owns how it filters and shapes the results.
module WebResearch
  class Error < StandardError; end

  # Without YDC_API_KEY every request is anonymous and shares one global free-tier
  # bucket, so it fails under load and never appears in your You.com analytics.
  API_KEY = ENV.fetch('YDC_API_KEY', nil)
  ANONYMOUS_URL = 'https://api.you.com/mcp?profile=free'
  AUTHENTICATED_URL = 'https://api.you.com/mcp'
  URL = ENV.fetch('RUBYLLM_TEAM_RESEARCH_MCP_URL') { API_KEY ? AUTHENTICATED_URL : ANONYMOUS_URL }
  TIMEOUT_SECONDS = Integer(ENV.fetch('RUBYLLM_TEAM_RESEARCH_TIMEOUT', '30'))

  class << self
    def tools
      @tools ||= client.tools
    end

    # Returns the raw You.com web result pages for one bounded search.
    def search(query:, include_domains: nil, count: 3)
      web_pages(execute_search(query, include_domains, count))
    end

    def close
      @client&.stop
    ensure
      @client = nil
      @tools = nil
    end

    private

    def execute_search(query, include_domains, count)
      params = {
        query: query, count: count,
        extraction: { extraction_mode: 'highlights' }, crawl_timeout: 10
      }
      params[:include_domains] = include_domains if include_domains
      search_tool.execute(**params)
    end

    def web_pages(result)
      raise Error, result[:error] || result['error'] if result.is_a?(Hash)

      pages = JSON.parse(result.to_s).dig('results', 'web')
      raise Error, 'You.com returned no web results' if Array(pages).empty?

      pages
    rescue JSON::ParserError, KeyError => e
      raise Error, "You.com returned malformed research: #{e.message}"
    end

    def search_tool
      tools.find { |tool| tool.name == 'you-search' } || raise(Error, 'You.com exposed no you-search tool')
    end

    def client
      @client ||= RubyLLM::MCP.client(
        name: 'you-search',
        transport_type: :streamable,
        request_timeout: TIMEOUT_SECONDS * 1000,
        config: { url: URL, headers: auth_headers }
      )
    end

    def auth_headers
      API_KEY ? { 'Authorization' => "Bearer #{API_KEY}" } : {}
    end
  end
end
