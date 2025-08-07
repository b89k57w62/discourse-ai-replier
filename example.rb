# =================================================================
# 檔案路徑: plugins/discourse-ai-replier/plugin.rb
# =================================================================
# frozen_string_literal: true

# name: discourse-ai-replier
# about: Uses AI to reply to topics to increase engagement.
# version: 0.2
# authors: Your Name
# url: https://github.com/your-repo

# -- [變更] 引入 Faraday gem --
# Discourse 會處理這些 gem 的安裝與載入
gem 'faraday', '2.9.0', require: false
gem 'faraday-json', '0.8.0', require: false

enabled_site_setting :ai_replier_enabled

# 載入所有相依的檔案
# 使用 `require_relative` 確保在開發模式下也能正確載入
require_relative 'app/jobs/scheduled/ai_topic_selector_job'
require_relative 'app/jobs/regular/ai_create_reply_job'
require_relative 'lib/ai_replier/topic_selector'
require_relative 'lib/ai_replier/ai_client'
require_relative 'lib/ai_replier/replier'

after_initialize do
  # 在 Discourse 初始化後執行的程式碼

  # 註冊排程任務
  # 根據指示，每小時執行一次選題 Job
  Jobs.schedule('ai_topic_selector', 1.hour)
end

# =================================================================
# 檔案路徑: plugins/discourse-ai-replier/config/settings.yml
# =================================================================

plugins:
  ai_replier_enabled:
    default: false
    client: true
  ai_replier_api_key:
    default: ""
    client: false
    secret: true
  ai_replier_api_url:
    default: "https://api.openai.com/v1/chat/completions" # 可以是任何 AI API 的 URL
    client: false
  ai_replier_model:
    default: "gpt-3.5-turbo"
    client: false
  ai_replier_system_prompt:
    default: "你是一個論壇的資深成員，你的目標是針對主題提供一個簡短、友善、能引發討論的回覆。請不要表明你是 AI。回覆請使用繁體中文。"
    client: false
    textarea: true


# =================================================================
# 檔案路徑: plugins/discourse-ai-replier/app/jobs/scheduled/ai_topic_selector_job.rb
# [路徑修正] 將檔案移至 app/jobs/... 以符合 Discourse 慣例
# =================================================================

module Jobs
  class AiTopicSelector < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      # 確保功能已啟用
      return unless SiteSetting.ai_replier_enabled?

      # 呼叫獨立的選題模組來獲取主題
      # 這讓 Job 本身保持乾淨，只做調度
      selected_topics = ::AiReplier::TopicSelector.select(limit: 10)

      selected_topics.each do |topic|
        # 為每一個選出的主題，分派一個獨立的 Job 去處理
        # 這樣可以並行處理，且單一回覆失敗不影響其他
        Jobs.enqueue(:ai_create_reply, topic_id: topic.id)
      end
    end
  end
end


# =================================================================
# 檔案路徑: plugins/discourse-ai-replier/app/jobs/regular/ai_create_reply_job.rb
# =================================================================

module Jobs
  class AiCreateReply < ::Jobs::Base
    def execute(args)
      topic_id = args[:topic_id]
      raise "topic_id is required" if topic_id.blank?

      # 確保功能已啟用
      return unless SiteSetting.ai_replier_enabled?

      topic = Topic.find_by(id: topic_id)
      # 如果主題不存在或不符合基本條件，則直接結束
      return if topic.blank? || topic.closed? || topic.archived?

      # 呼叫獨立的 Replier 模組來執行所有核心邏輯
      # Job 只負責傳遞參數和觸發，職責單一
      ::AiReplier::Replier.reply_to(topic)
    end
  end
end


# =================================================================
# 檔案路徑: plugins/discourse-ai-replier/lib/ai_replier/topic_selector.rb
# =================================================================

module AiReplier
  class TopicSelector
    # 核心選題邏輯
    def self.select(limit: 10)
      # 執行瀑布流策略
      # 1. 嘗試策略一
      topics = new_and_quiet_topics(limit)

      # 2. 如果策略一沒結果，嘗試策略二
      if topics.empty?
        topics = older_worthy_topics(limit)
      end

      topics
    end

    private

    # 策略一：活化新帖與冷門帖
    def self.new_and_quiet_topics(limit)
      base_scope
        .where("posts_count <= 5")
        .order(created_at: :desc)
        .limit(limit)
    end

    # 策略二：活化沉寂的舊文
    def self.older_worthy_topics(limit)
      base_scope
        .where("last_posted_at < ?", 3.days.ago)
        .where("views > ?", 50)
        .order(last_posted_at: :desc)
        .limit(limit)
    end

    # 共通的查詢基礎 (Base Scope)
    # 所有選題策略都從這裡開始，確保基本過濾條件一致
    def self.base_scope
      ai_user_ids = User.where("username LIKE 'fungps%'").pluck(:id)

      Topic
        .where(archetype: Archetype.default)
        .where(closed: false, archived: false)
        .where.not(id: Post.where(user_id: ai_user_ids).select(:topic_id)) # 排除已被任一 AI 帳號回覆過的主題
    end
  end
end


# =================================================================
# 檔案路徑: plugins/discourse-ai-replier/lib/ai_replier/replier.rb
# =================================================================

module AiReplier
  class Replier
    def self.reply_to(topic)
      # 1. 取得 AI 使用者帳號
      ai_user = User.where("username LIKE 'fungps%'").sample
      return unless ai_user # 如果找不到任何 AI 帳號，則終止

      # 2. 準備 Prompt
      # 只拿第一篇原文當作上下文，保持簡單
      prompt = topic.first_post.raw

      # 3. 呼叫 AI Client 取得回覆內容
      reply_content = AiReplier::AiClient.generate_reply(prompt)
      return if reply_content.blank? # 如果 AI 沒有回傳內容，則終止

      # 4. 使用 PostCreator 建立回覆
      # 這是 Discourse 建立貼文的標準、安全作法
      post_creator = PostCreator.new(
        ai_user,
        topic_id: topic.id,
        raw: reply_content
      )
      post_creator.create
    end
  end
end


# =================================================================
# 檔案路徑: plugins/discourse-ai-replier/lib/ai_replier/ai_client.rb
# -- [變更] 使用 Faraday 重構 --
# =================================================================

require 'faraday'
require 'faraday/net_http'
require 'faraday/json'

module AiReplier
  class AiClient
    # 負責與外部 AI API 溝通
    def self.generate_reply(prompt)
      api_key = SiteSetting.ai_replier_api_key
      api_url = SiteSetting.ai_replier_api_url
      model = SiteSetting.ai_replier_model
      system_prompt = SiteSetting.ai_replier_system_prompt

      # 檢查必要設定
      return if api_key.blank? || api_url.blank?

      # 使用 Faraday 建立連線物件，並設定中介軟體 (Middleware)
      conn = Faraday.new do |faraday|
        faraday.request :json # 自動將請求 body 編碼為 JSON
        faraday.response :json # 自動將回應 body 解析為 Hash
        faraday.response :raise_error # 當 HTTP 狀態為 4xx 或 5xx 時拋出例外
        faraday.adapter Faraday.default_adapter # 使用預設的 HTTP 轉接器
      end

      # 執行 POST 請求
      response = conn.post(api_url) do |req|
        req.headers['Authorization'] = "Bearer #{api_key}"
        req.headers['Content-Type'] = 'application/json'
        req.body = {
          "model" => model,
          "messages" => [
            { "role" => "system", "content" => system_prompt },
            { "role" => "user", "content" => prompt }
          ]
        }
      end

      # 直接從已解析的回應中取得內容
      response.body.dig("choices", 0, "message", "content")

    # 捕捉 Faraday 可能拋出的各種錯誤
    rescue Faraday::Error => e
      Rails.logger.error("AI Replier Faraday Error: #{e.message} | Response: #{e.response&.[:body]}")
      return nil
    # 捕捉其他可能的例外
    rescue => e
      Rails.logger.error("AI Replier Exception: #{e.message}")
      return nil
    end
  end
end
