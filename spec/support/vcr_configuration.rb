# frozen_string_literal: true

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!
  record_mode = ENV.fetch('VCR_RECORD_MODE', ENV['CI'] ? 'none' : 'once').to_sym

  # Handoffs are fenced with a per-session random nonce, which would otherwise make every
  # recorded body unmatchable. Normalise the nonce, then compare bodies exactly: request
  # bodies embed the accumulated trace, so a prompt change should still invalidate the
  # cassette — re-record with VCR_RECORD_MODE=all rather than loosening this further.
  fence = /--- (result|end) \h+/
  config.register_request_matcher :fenced_body do |recorded, actual|
    recorded.body.gsub(fence, '--- \1 FENCE') == actual.body.gsub(fence, '--- \1 FENCE')
  end
  config.default_cassette_options = {
    record: record_mode, match_requests_on: %i[method uri fenced_body]
  }
  config.allow_http_connections_when_no_cassette = false
  config.filter_sensitive_data('<OPENROUTER_API_KEY>') { ENV['OPENROUTER_API_KEY'] }

  config.before_record do |interaction|
    interaction.request.headers['Authorization'] = ['Bearer <OPENROUTER_API_KEY>']
    %w[Date Set-Cookie X-Generation-Id Cf-Ray].each do |header|
      interaction.response.headers.delete(header)
    end
  end
end
