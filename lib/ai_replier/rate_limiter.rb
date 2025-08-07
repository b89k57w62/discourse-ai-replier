# frozen_string_literal: true

module AiReplier
  class RateLimiter
    RATE_LIMIT_KEY = "ai_replier:rate_limit"
    COOLDOWN_KEY_PREFIX = "ai_replier:cooldown:topic:"

    class RateLimitExceeded < StandardError; end

    class << self
      def can_make_request?
        current_count < max_requests_per_hour
      end

      def increment_request_count!
        raise RateLimitExceeded unless can_make_request?
        
        key = rate_limit_key
        Discourse.redis.multi do |redis|
          redis.incr(key)
          redis.expire(key, 1.hour.to_i)
        end
      end

      def current_count
        Discourse.redis.get(rate_limit_key).to_i
      end

      def topic_in_cooldown?(topic_id)
        Discourse.redis.exists?(cooldown_key(topic_id))
      end

      def set_topic_cooldown(topic_id)
        cooldown_hours = SiteSetting.ai_replier_cooldown_hours
        Discourse.redis.setex(
          cooldown_key(topic_id),
          cooldown_hours.hours.to_i,
          Time.current.to_i
        )
      end

      def clear_topic_cooldown(topic_id)
        Discourse.redis.del(cooldown_key(topic_id))
      end

      def clear_all_cooldowns
        keys = Discourse.redis.keys("#{COOLDOWN_KEY_PREFIX}*")
        Discourse.redis.del(*keys) if keys.any?
      end

      def cooldown_remaining(topic_id)
        ttl = Discourse.redis.ttl(cooldown_key(topic_id))
        ttl > 0 ? ttl : 0
      end

      def reset_rate_limit
        Discourse.redis.del(rate_limit_key)
      end

      def stats
        {
          current_hour_count: current_count,
          max_per_hour: max_requests_per_hour,
          remaining_requests: [max_requests_per_hour - current_count, 0].max,
          cooldown_topics: cooldown_topic_count
        }
      end

      private

      def rate_limit_key
        hour_bucket = Time.current.strftime("%Y%m%d%H")
        "#{RATE_LIMIT_KEY}:#{hour_bucket}"
      end

      def cooldown_key(topic_id)
        "#{COOLDOWN_KEY_PREFIX}#{topic_id}"
      end

      def max_requests_per_hour
        SiteSetting.ai_replier_rate_limit_per_hour
      end

      def cooldown_topic_count
        Discourse.redis.keys("#{COOLDOWN_KEY_PREFIX}*").count
      end
    end
  end
end