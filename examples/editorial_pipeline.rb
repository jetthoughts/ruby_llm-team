# frozen_string_literal: true

require_relative 'support/example_runner'
require_relative 'topic_analyst/workflow'
require_relative 'blog/workflow'

# Connects the two example teams: the analyst ranks what to write, the blog team writes the
# top pick. There is no higher-order Team API here on purpose — composing two runs is Ruby.
# Each run keeps its own budget, trace, and failure boundary; the plan is passed as data.
module EditorialPipeline
  PLAN_PATH = File.join(__dir__, 'topic_analyst', 'plan.md')
  POST_PATH = File.join(__dir__, 'blog', 'output.md')
  TRACE_PATH = File.join(__dir__, 'blog', 'pipeline_trace.md')
  CHOICE_TRACE_PATH = File.join(__dir__, 'topic_analyst', 'choice_trace.md')

  CHOOSER_INSTRUCTIONS = <<~PROMPT
    You decide which post the team writes next from a ranked shortlist. The ranking is a
    starting point, not an instruction: the analyst that produced it saw one lens at a time.

    Consult the analysts with ask_question only where their lens would actually change your
    mind — every consultation costs money and your budget is small. Then answer with one line:

    PICK: <the exact title, copied verbatim>

    followed by one sentence on why it beats the runner-up.
  PROMPT

  module_function

  # The analyst ranks candidates from one lens at a time. Rather than betting on its top row,
  # a lead model argues the shortlist out with those same analysts and picks. Nothing here
  # orchestrates that conversation — the model decides who is worth asking.
  def choose(plan, chat: nil, team: TopicAnalyst::Workflow.build_team)
    candidates = Array(plan['recommendations'])
    return [candidates.first, nil] if candidates.length < 2

    session = team.session(max_calls: 3, context: TopicAnalyst::ANALYST_CONTEXT)
    verdict = lead(session, chat).ask(shortlist(candidates)).content.to_s
    [candidates.find { |item| verdict.include?(item.fetch('title')) } || candidates.first, session]
  end

  def lead(session, chat)
    (chat || RubyLLM.chat(model: TopicAnalyst::MODEL, provider: :openrouter, assume_model_exists: true))
      .with_tools(*session.tools)
      .with_instructions(CHOOSER_INSTRUCTIONS)
  end

  def shortlist(candidates)
    rows = candidates.map.with_index(1) do |item, rank|
      "#{rank}. #{item.fetch('title')} — pain: #{item['reader_pain']} — angle: #{item['angle']}"
    end
    "Choose the post to write next:\n#{rows.join("\n")}"
  end

  # Turns one analyst recommendation into the blog team's brief.
  def brief_for(recommendation)
    <<~CONTEXT
      Article brief:
      Audience: production Ruby developers using RubyLLM.
      Working title: #{recommendation.fetch('title')}
      Reader need: #{recommendation.fetch('reader_pain')}
      Required insight: #{recommendation.fetch('angle')}
      Target: a practical 250-350 word Markdown article with one tested Ruby example.
      Evidence pack:
      Analyst evidence: #{Array(recommendation['evidence_urls']).join(', ')}
      Author basis: this article is written from the researched public sources handed to
      you, not from personal history. Attribute every claim to a researched source or
      state its limit plainly; a bounded, sourced observation is authentic here, and an
      invented anecdote, client, or metric is not.
      Voice ledger:
      #{VOICE_LEDGER}
      Online research policy:
      #{RESEARCH_POLICY}
    CONTEXT
  end

  # The blog's default contract demands retry-article text; a new topic needs its own.
  # Outcome over output: the editors judge whether the article is worth reading. The only
  # deterministic checks kept are the ones a reader cannot forgive — unfinished
  # placeholders and Ruby that does not parse. Word counts and heading shapes are not
  # quality, and failing a run over them throws away good writing.
  def contract_for
    BlogPublicationContract.new(ruby_examples: 1, forbid_placeholders: true)
  end

  # The blog's default plan searches rubyllm.com for retry keywords. An analyst topic needs
  # the open web and every highlight, or the evidence can never support its thesis.
  def research_for(recommendation)
    ResearchPlan.new(query: recommendation.fetch('title'), domains: nil, highlight_filter: nil)
  end

  def blog_workflow_for(recommendation, on_step:)
    BlogWorkflow.new(
      context: brief_for(recommendation),
      research: research_for(recommendation),
      validator: BlogPublicationValidator.new(contract: contract_for),
      # A pipeline draft is worth having with its gate failures disclosed; only the
      # flagship article refuses to publish anything that misses a gate.
      quality_policy: :best_effort,
      on_step: on_step
    )
  end

  def article_with_warnings(workflow)
    post = workflow.run
    return post if workflow.quality_warnings.empty?

    "#{post}\n\n## Quality warnings\n\n- #{workflow.quality_warnings.join("\n- ")}"
  end
end

def plan_next_posts(domain)
  plan = TopicAnalyst::Workflow.new.call(domain)
  ExampleRunner.save(EditorialPipeline::PLAN_PATH, "# Next posts for #{domain}\n\n#{format_plan(plan)}")

  choice, session = EditorialPipeline.choose(plan)
  ExampleRunner.save_trace(session, 'choice', EditorialPipeline::CHOICE_TRACE_PATH) if session
  choice
end

def write_top_pick(recommendation)
  warn "[team] Writing the top pick: #{recommendation.fetch('title')}"
  workflow = EditorialPipeline.blog_workflow_for(
    recommendation, on_step: ->(step) { warn "[team] #{step}" }
  )
  ExampleRunner.run(
    label: 'article', output_path: EditorialPipeline::POST_PATH,
    trace_path: EditorialPipeline::TRACE_PATH, workflow: workflow,
    rescue_from: [BlogResearch::Error, BlogWorkflowError, Timeout::Error, Faraday::Error]
  ) { EditorialPipeline.article_with_warnings(workflow) }
end

# Researches a domain, then writes the top-ranked post.
def run_editorial_pipeline(domain = ARGV.join(' '))
  abort 'Usage: ruby examples/editorial_pipeline.rb "your domain"' if domain.to_s.strip.empty?

  ExampleRunner.configure
  write_top_pick(plan_next_posts(domain))
rescue WebResearch::Error, RubyLLM::Team::CollaborationError => e
  abort "[team] Editorial pipeline failed: #{e.message}"
ensure
  WebResearch.close
end

run_editorial_pipeline if $PROGRAM_NAME == __FILE__
