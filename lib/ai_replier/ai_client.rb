# frozen_string_literal: true

require 'faraday'
require 'faraday/net_http'

module AiReplier
  class AiClient
    class ApiError < StandardError; end
    class ConfigurationError < StandardError; end
    
    class << self
      def generate_reply(prompt)
        validate_configuration!

        unless RateLimiter.can_make_request?
          Rails.logger.warn("AI Replier: Rate limit exceeded, skipping request")
          return nil
        end
        
        response = make_api_request(prompt)
        
        reply = extract_reply(response)
        
        RateLimiter.increment_request_count!
        
        reply
      rescue Faraday::Error => e
        handle_api_error(e)
        nil
      rescue => e
        Rails.logger.error("AI Replier unexpected error: #{e.message}")
        HealthChecker.record_failure(:api_request, e.message)
        nil
      end
      
      def test_connection
        validate_configuration!
        
        conn = build_connection(timeout: 5)
        response = conn.post(api_url) do |req|
          configure_request(req, "Test", max_tokens: 5)
        end
        
        response.status == 200
      rescue => e
        Rails.logger.error("AI Replier connection test failed: #{e.message}")
        false
      end
      
      private
      
      def validate_configuration!
        raise ConfigurationError, "API key not configured" if api_key.blank?
        raise ConfigurationError, "API URL not configured" if api_url.blank?
        raise ConfigurationError, "Model not configured" if model.blank?
      end
      
      def make_api_request(prompt)
        conn = build_connection
        
        retries = 0
        max_retries = SiteSetting.ai_replier_max_retries
        
        begin
          response = conn.post(api_url) do |req|
            configure_request(req, prompt)
          end
          
          HealthChecker.record_success(:api_request)
          response
        rescue Faraday::Error => e
          retries += 1
          if retries < max_retries
            wait_time = (2 ** retries) + rand(0..1.0)
            Rails.logger.info("AI Replier: Retrying after #{wait_time}s (attempt #{retries}/#{max_retries})")
            sleep(wait_time)
            retry
          else
            raise e
          end
        end
      end
      
      def build_connection(timeout: nil)
        timeout ||= SiteSetting.ai_replier_request_timeout
        
        Faraday.new do |faraday|
          faraday.request :json
          faraday.response :json
          faraday.response :raise_error
          faraday.adapter Faraday.default_adapter
          faraday.options.timeout = timeout
          faraday.options.open_timeout = timeout / 2
        end
      end
      
      def configure_request(req, prompt, max_tokens: nil)
        req.headers['Authorization'] = "Bearer #{api_key}"
        req.headers['Content-Type'] = 'application/json'
        
        req.body = build_request_body(prompt, max_tokens)
      end
      
      def build_request_body(prompt, max_tokens)
        body = {
          model: model,
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: prompt }
          ],
          temperature: 0.7,
          top_p: 0.9,
          frequency_penalty: 0.3,
          presence_penalty: 0.3
        }
        
        body[:max_tokens] = max_tokens if max_tokens
        
        body
      end
      
      def extract_reply(response)
        content = response.body.dig("choices", 0, "message", "content")
        
        if content.blank?
          Rails.logger.error("AI Replier: Empty response from API")
          return nil
        end
        
        content.strip
      end
      
      
      def handle_api_error(error)
        error_message = "#{error.class}: #{error.message}"
        
        if error.response
          status = error.response[:status]
          body = error.response[:body]
          
          case status
          when 401
            Rails.logger.error("AI Replier: Invalid API key")
            HealthChecker.record_failure(:api_auth, "Invalid API key")
          when 429
            Rails.logger.warn("AI Replier: API rate limit exceeded")
            HealthChecker.record_failure(:api_rate_limit, "API rate limit")
          when 500..599
            Rails.logger.error("AI Replier: API server error (#{status})")
            HealthChecker.record_failure(:api_server, "Server error #{status}")
          else
            Rails.logger.error("AI Replier API error: #{error_message}")
            Rails.logger.error("Response body: #{body}") if body
            HealthChecker.record_failure(:api_request, error_message)
          end
        else
          Rails.logger.error("AI Replier network error: #{error_message}")
          HealthChecker.record_failure(:api_network, error_message)
        end
      end
      
      def api_key
        SiteSetting.ai_replier_api_key
      end
      
      def api_url
        SiteSetting.ai_replier_api_url
      end
      
      def model
        SiteSetting.ai_replier_model
      end
      
      def system_prompt
        SiteSetting.ai_replier_system_prompt
      end
    end
  end
end