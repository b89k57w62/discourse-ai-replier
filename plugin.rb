# frozen_string_literal: true
# name: discourse-ai-replier
# about: Uses AI to automatically reply to topics to increase engagement
# version: 1.0.0
# authors: Jeffrey
# url: https://github.com/b89k57w62/discourse-ai-replier

enabled_site_setting :ai_replier_enabled

after_initialize do
  load File.expand_path('../lib/ai_replier/rate_limiter.rb', __FILE__)
  load File.expand_path('../lib/ai_replier/health_checker.rb', __FILE__)
  load File.expand_path('../lib/ai_replier/topic_selector.rb', __FILE__)
  load File.expand_path('../lib/ai_replier/ai_client.rb', __FILE__)
  load File.expand_path('../lib/ai_replier/replier.rb', __FILE__)

  load File.expand_path('../app/jobs/scheduled/ai_topic_selector_job.rb', __FILE__)
  load File.expand_path('../app/jobs/regular/ai_create_reply_job.rb', __FILE__)
end