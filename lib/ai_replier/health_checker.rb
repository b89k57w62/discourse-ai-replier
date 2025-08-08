# frozen_string_literal: true

module AiReplier
  class HealthChecker
    HEALTH_CHECK_KEY = "ai_replier:health"
    API_HEALTH_KEY = "ai_replier:api_health"
    
    class << self
      def check
        {
          enabled: plugin_enabled?,
          api_configured: api_configured?,
          api_healthy: api_healthy?,
          ai_users_available: ai_users_available?,
          rate_limit_ok: rate_limit_ok?,
          last_check: last_health_check_time,
          errors: collect_errors
        }
      end

      def plugin_enabled?
        SiteSetting.ai_replier_enabled?
      end

      def api_configured?
        SiteSetting.ai_replier_api_key.present? &&
          SiteSetting.ai_replier_api_url.present? &&
          SiteSetting.ai_replier_model.present?
      end

      def api_healthy?
        api_configured?
      end

      def test_api_connection
        api_configured?
      end

      def ai_users_available?
        ai_users.count > 0
      end

      def ai_users
        User.joins(:user_emails).where("user_emails.email LIKE 'fungps%'")
      end

      def rate_limit_ok?
        RateLimiter.can_make_request?
      end

      def stats
        {
          total_ai_users: ai_users.count,
          active_ai_users: active_ai_users.count,
          rate_limit_stats: RateLimiter.stats,
          recent_replies: recent_replies_count,
          success_rate: calculate_success_rate
        }
      end

      def ready?
        plugin_enabled? && 
          api_configured? && 
          ai_users_available? && 
          rate_limit_ok?
      end

      def record_success(operation_type)
        key = "ai_replier:stats:success:#{operation_type}:#{Date.current}"
        Discourse.redis.incr(key)
        Discourse.redis.expire(key, 7.days.to_i)
      end
      
      def record_failure(operation_type, error_message = nil)
        key = "ai_replier:stats:failure:#{operation_type}:#{Date.current}"
        Discourse.redis.incr(key)
        Discourse.redis.expire(key, 7.days.to_i)
        
        if error_message
          error_key = "ai_replier:errors:#{Time.current.to_i}"
          Discourse.redis.setex(error_key, 1.day.to_i, error_message)
        end
      end

      private

      # 移除缓存方法，因为不再需要API健康状态缓存
      # def cache_api_health(is_healthy)
      #   status = is_healthy ? "healthy" : "unhealthy"
      #   Discourse.redis.setex(API_HEALTH_KEY, 5.minutes.to_i, status)
      # end

      def last_health_check_time
        Discourse.redis.get("#{HEALTH_CHECK_KEY}:last_check")
      end

      def active_ai_users
        ai_users.where("last_seen_at > ?", 7.days.ago)
      end

      def recent_replies_count
        return 0 unless ai_users_available?
        
        Post.where(user_id: ai_users.pluck(:id))
            .where("created_at > ?", 24.hours.ago)
            .count
      end

      def calculate_success_rate
        today = Date.current
        success_key = "ai_replier:stats:success:reply:#{today}"
        failure_key = "ai_replier:stats:failure:reply:#{today}"
        
        successes = Discourse.redis.get(success_key).to_i
        failures = Discourse.redis.get(failure_key).to_i
        total = successes + failures
        
        return 100.0 if total == 0
        (successes.to_f / total * 100).round(2)
      end

      def collect_errors
        errors = []
        errors << I18n.t("ai_replier.errors.api_key_missing") unless SiteSetting.ai_replier_api_key.present?
        errors << I18n.t("ai_replier.errors.api_url_missing") unless SiteSetting.ai_replier_api_url.present?
        errors << I18n.t("ai_replier.errors.user_not_found") unless ai_users_available?
        errors << I18n.t("ai_replier.errors.rate_limit_exceeded") unless rate_limit_ok?
        errors
      end
    end
  end
end