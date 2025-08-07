# frozen_string_literal: true

module AiReplier
  class Replier
    class ReplyError < StandardError; end
    
    class << self
      def reply_to(topic)
        return unless topic.present?
        
        unless can_reply_to?(topic)
          Rails.logger.info("AI Replier: Topic ##{topic.id} not suitable for reply")
          return false
        end
        
        ai_user = select_ai_user
        unless ai_user
          Rails.logger.error("AI Replier: No AI user available")
          HealthChecker.record_failure(:reply, "No AI user available")
          return false
        end
        
        prompt = prepare_prompt(topic)
        
        reply_content = AiClient.generate_reply(prompt)
        
        if reply_content.blank?
          Rails.logger.warn("AI Replier: Failed to generate reply for topic ##{topic.id}")
          HealthChecker.record_failure(:reply, "Empty AI response")
          return false
        end
        
        post = create_post(ai_user, topic, reply_content)
        if post.persisted?
          RateLimiter.set_topic_cooldown(topic.id)
          
          Rails.logger.info("AI Replier: Successfully created reply for topic ##{topic.id} (post ##{post.id})")
          HealthChecker.record_success(:reply)
          
          true
        else
          error_msg = post.errors.full_messages.join(", ")
          Rails.logger.error("AI Replier: Failed to create post for topic ##{topic.id}: #{error_msg}")
          HealthChecker.record_failure(:reply, error_msg)
          false
        end
        
      rescue => e
        Rails.logger.error("AI Replier error for topic ##{topic.id}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        HealthChecker.record_failure(:reply, e.message)
        false
      end
      
      private
      
      def can_reply_to?(topic)
        return false if topic.closed? || topic.archived?
        
        return false if topic.deleted_at.present?
        
        return false if topic.archetype == Archetype.private_message
        
        return false if RateLimiter.topic_in_cooldown?(topic.id)
        
        min_age_hours = SiteSetting.ai_replier_min_topic_age_hours
        if min_age_hours > 0
          return false if topic.created_at > min_age_hours.hours.ago
        end
        
        true
      end
      
      def select_ai_user
        ai_users = HealthChecker.ai_users.to_a
        return nil if ai_users.empty?
        
        ai_users.sample
      end
      
      def prepare_prompt(topic)
        first_post = topic.first_post
        return "" unless first_post
        
        first_post.raw
      end
      
      def create_post(user, topic, content)
        post_creator = PostCreator.new(
          user,
          topic_id: topic.id,
          raw: content,
          skip_validations: false,
          skip_jobs: false
        )
        
        post_creator.create
      end
    end
  end
end