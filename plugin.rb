# frozen_string_literal: true

# name: discourse-ai-replier
# about: Uses AI to automatically reply to topics to increase engagement
# version: 1.0.0
# authors: Jeffrey
# url: https://github.com/b89k57w62/discourse-ai-replier

enabled_site_setting :ai_replier_enabled

gem 'faraday', '2.9.0', require: false
gem 'faraday-net_http', '3.0.2', require: false

register_asset 'stylesheets/discourse-ai-replier.scss'

after_initialize do
  # Load core modules
  %w[
    lib/ai_replier/rate_limiter
    lib/ai_replier/health_checker
    lib/ai_replier/topic_selector
    lib/ai_replier/ai_client
    lib/ai_replier/replier
  ].each do |file|
    require_relative file
  end

  # Load jobs
  %w[
    app/jobs/scheduled/ai_topic_selector_job
    app/jobs/regular/ai_create_reply_job
  ].each do |file|
    require_relative file
  end

  # The scheduled job will be automatically registered by Discourse
  # due to the `every 1.hour` declaration in AiTopicSelector class
  # No need to manually enqueue or check settings here
end