# frozen_string_literal: true

module Jobs
  class AiTopicSelector < ::Jobs::Scheduled
    every 3.minutes

    def execute(args)
      # Ensure plugin is enabled
      return unless SiteSetting.ai_replier_enabled?
      
      # Check system health before proceeding
      unless AiReplier::HealthChecker.ready?
        Rails.logger.warn("AI Replier: System not ready, skipping topic selection")
        return
      end
      
      Rails.logger.info(I18n.t("ai_replier.logs.job_started"))
      
      # Select topics using waterfall strategy
      selected_topics = AiReplier::TopicSelector.select
      
      if selected_topics.empty?
        Rails.logger.info("AI Replier: No suitable topics found for AI replies")
        return
      end
      
      Rails.logger.info(I18n.t("ai_replier.logs.topic_selected", count: selected_topics.count))
      
      # Enqueue individual jobs for each selected topic
      selected_topics.each do |topic|
        Jobs.enqueue(:ai_create_reply, topic_id: topic.id)
      end
      
      Rails.logger.info(I18n.t("ai_replier.logs.job_completed"))
      
    rescue => e
      Rails.logger.error("AI Topic Selector Job error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      AiReplier::HealthChecker.record_failure(:job_selector, e.message)
    end
  end
end