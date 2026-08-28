# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require_relative '../../examples/simple_team'

RSpec.describe SimpleTeamExample do
  it 'hands the completed plan to the reviewer and records the run' do
    output = StringIO.new

    execution = described_class.run(output: output)

    expect(execution.calls.map(&:coworker)).to eq(%w[planner reviewer])
    expect(execution.calls.last.inputs).to eq(['plan@v1 (planner)'])
    expect(execution.calls.last.prompt).to include(execution.value(:plan))
    expect(execution.output).to start_with('Approved:')
    expect(output.string).to include('## 2. reviewer via delegate_work')
  end
end
