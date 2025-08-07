# frozen_string_literal: true

module Jobs
  class AiCreateReply < ::Jobs::Base
    def execute(args)
      topic_id = args[:topic_id]
      
      # Validate required parameter
      if topic_id.blank?
        Rails.logger.error("AI Create Reply Job: topic_id is required")
        return
      end
      
      # Ensure plugin is enabled
      return unless SiteSetting.ai_replier_enabled?
      
      # Find the topic
      topic = Topic.find_by(id: topic_id)
      
      if topic.blank?
        Rails.logger.warn("AI Create Reply Job: Topic ##{topic_id} not found")
        return
      end
      
      # Double-check topic is still valid for reply
      if topic.closed? || topic.archived? || topic.deleted_at.present?
        Rails.logger.info("AI Create Reply Job: Topic ##{topic_id} is no longer valid for reply")
        return
      end
      
      # Call the replier to handle the actual reply logic
      success = AiReplier::Replier.reply_to(topic)
      
      if success
        Rails.logger.info(I18n.t("ai_replier.logs.reply_created", topic_id: topic_id))
      else
        Rails.logger.warn(I18n.t("ai_replier.logs.reply_failed", 
                                  topic_id: topic_id, 
                                  error: "Check logs for details"))
      end
      
    rescue => e
      Rails.logger.error("AI Create Reply Job error for topic ##{topic_id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      AiReplier::HealthChecker.record_failure(:job_reply, e.message)
    end
  end
end