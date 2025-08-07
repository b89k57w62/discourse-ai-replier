# frozen_string_literal: true

module AiReplier
  class TopicSelector
    class << self
      def select(limit: nil)
        limit ||= SiteSetting.ai_replier_batch_size
        
        topics = []
        
        topics = new_and_quiet_topics(limit)
        
        if topics.empty?
          topics = older_worthy_topics(limit)
        end
        
        topics = filter_cooldown_topics(topics)
        
        topics = filter_by_age(topics)
        
        Rails.logger.info("AI Replier: Selected #{topics.count} topics for processing")
        topics
      end

      private

      def new_and_quiet_topics(limit)
        max_posts = SiteSetting.ai_replier_quiet_topic_max_posts
        
        base_scope
          .where("posts_count <= ?", max_posts)
          .order(created_at: :desc)
          .limit(limit)
          .to_a
      end

      def older_worthy_topics(limit)
        days_threshold = SiteSetting.ai_replier_old_topic_days
        min_views = SiteSetting.ai_replier_old_topic_min_views
        
        base_scope
          .where("last_posted_at < ?", days_threshold.days.ago)
          .where("views >= ?", min_views)
          .order(last_posted_at: :desc)
          .limit(limit)
          .to_a
      end

      def base_scope
        scope = Topic.where(archetype: Archetype.default)
                     .where(closed: false, archived: false)
                     .where(deleted_at: nil)
                     .joins(:first_post)
                     .where(posts: { deleted_at: nil })
        
        scope = scope.where("topics.archetype != ?", Archetype.private_message)
        
        scope = scope.where.not(user_id: Discourse.system_user.id)
        
        scope
      end

      def filter_cooldown_topics(topics)
        topics.reject do |topic|
          RateLimiter.topic_in_cooldown?(topic.id)
        end
      end

      def filter_by_age(topics)
        min_age_hours = SiteSetting.ai_replier_min_topic_age_hours
        return topics if min_age_hours == 0
        
        cutoff_time = min_age_hours.hours.ago
        topics.select do |topic|
          topic.created_at <= cutoff_time
        end
      end

      def self.stats
        ai_user_ids = HealthChecker.ai_users.pluck(:id)
        
        base_count = base_scope.count
        quiet_count = new_and_quiet_topics(1000).count
        old_count = older_worthy_topics(1000).count
        
        cooldown_count = 0
        Topic.find_each do |topic|
          cooldown_count += 1 if RateLimiter.topic_in_cooldown?(topic.id)
        end

        recent_ai_activity = Post.where(user_id: ai_user_ids)
                                 .where("created_at > ?", 24.hours.ago)
                                 .select(:topic_id)
                                 .distinct
                                 .count
        
        {
          total_eligible: base_count,
          quiet_topics: quiet_count,
          old_topics: old_count,
          in_cooldown: cooldown_count,
          recent_ai_activity: recent_ai_activity,
          ai_users: ai_user_ids.count
        }
      end
    end
  end
end