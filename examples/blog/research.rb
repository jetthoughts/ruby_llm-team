# frozen_string_literal: true

require 'json'
require_relative '../support/web_research'

# Owns the blog example's evidence gathering on top of the shared web search.
module BlogResearch
  Error = WebResearch::Error
  TIMEOUT_SECONDS = WebResearch::TIMEOUT_SECONDS

  class << self
    def tools = WebResearch.tools
    def close = WebResearch.close

    # +highlight_filter+ narrows extracted highlights to one topic; pass nil to keep them all.
    def search_and_extract(query:, include_domains:, highlight_filter: nil)
      compact(WebResearch.search(query: query, include_domains: include_domains), highlight_filter)
    end

    private

    def compact(pages, highlight_filter)
      pages.map do |page|
        page.slice('title', 'url', 'page_age', 'snippets').merge(
          'highlights' => relevant_highlights(page, highlight_filter)
        )
      end
    end

    def relevant_highlights(page, highlight_filter)
      highlights = Array(page.dig('contents', 'highlights'))
      highlights = highlights.select { |text| text.match?(highlight_filter) } if highlight_filter
      highlights.first(8)
    end
  end
end

# Hides the provider's large MCP schema behind one small tool that weak models can call.
class SearchAndExtractSources < RubyLLM::Tool
  description 'Search current RubyLLM documentation and extract relevant page highlights.'
  param :query, desc: 'A focused search query of three to six words.'

  def execute(query:)
    JSON.generate(BlogResearch.search_and_extract(query: query, include_domains: ['rubyllm.com']))
  rescue BlogResearch::Error => e
    { error: e.message }
  end
end
