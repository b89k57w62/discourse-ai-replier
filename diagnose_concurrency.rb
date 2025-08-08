#!/usr/bin/env ruby
# frozen_string_literal: true

# AI Replier 并发诊断脚本
# 使用方法: 在Discourse Rails console中运行

puts "=== AI Replier 并发诊断 ==="
puts

# 1. 检查基本配置
puts "1. 基本配置检查:"
puts "   插件启用: #{SiteSetting.ai_replier_enabled?}"
puts "   批次大小: #{SiteSetting.ai_replier_batch_size}"
puts "   速率限制/小时: #{SiteSetting.ai_replier_rate_limit_per_hour}"
puts "   冷却期(小时): #{SiteSetting.ai_replier_cooldown_hours}"
puts "   最小主题年龄(小时): #{SiteSetting.ai_replier_min_topic_age_hours}"
puts

# 2. 检查AI用户
puts "2. AI用户检查:"
ai_users = User.joins(:user_emails).where("user_emails.email LIKE 'fungps%'")
puts "   AI用户总数: #{ai_users.count}"
if ai_users.any?
  puts "   AI用户列表:"
  ai_users.each do |user|
    puts "     - #{user.username} (ID: #{user.id})"
  end
else
  puts "   ⚠️  警告: 没有找到AI用户 (需要邮箱以'fungps'开头的用户)"
end
puts

# 3. 检查健康状态
puts "3. 系统健康检查:"
health_check = AiReplier::HealthChecker.check
health_check.each do |key, value|
  status = value ? "✅" : "❌"
  puts "   #{key}: #{status} #{value}"
end
puts

# 4. 检查速率限制
puts "4. 速率限制状态:"
rate_stats = AiReplier::RateLimiter.stats
rate_stats.each do |key, value|
  puts "   #{key}: #{value}"
end
puts

# 5. 检查主题选择过程
puts "5. 主题选择诊断:"
puts "   检查新且安静的主题..."

# 模拟主题选择过程
base_scope = Topic.where(archetype: Archetype.default)
                  .where(closed: false, archived: false)
                  .where(deleted_at: nil)
                  .joins(:first_post)
                  .where(posts: { deleted_at: nil })
                  .where("topics.archetype != ?", Archetype.private_message)
                  .where.not(user_id: Discourse.system_user.id)

puts "   基础符合条件的主题数: #{base_scope.count}"

# 检查新且安静的主题
max_posts = SiteSetting.ai_replier_quiet_topic_max_posts
quiet_topics = base_scope.where("posts_count <= ?", max_posts)
                         .order(created_at: :desc)
                         .limit(SiteSetting.ai_replier_batch_size)
puts "   新且安静的主题数 (帖子数<=#{max_posts}): #{quiet_topics.count}"

# 检查老且有价值的主题
days_threshold = SiteSetting.ai_replier_old_topic_days
min_views = SiteSetting.ai_replier_old_topic_min_views
old_topics = base_scope.where("last_posted_at < ?", days_threshold.days.ago)
                       .where("views >= ?", min_views)
                       .order(last_posted_at: :desc)
                       .limit(SiteSetting.ai_replier_batch_size)
puts "   老且有价值的主题数 (>=#{min_views}浏览量, #{days_threshold}天无活动): #{old_topics.count}"

# 检查冷却期
cooldown_count = 0
Topic.find_each do |topic|
  cooldown_count += 1 if AiReplier::RateLimiter.topic_in_cooldown?(topic.id)
end
puts "   在冷却期的主题数: #{cooldown_count}"
puts

# 6. 检查年龄过滤
puts "6. 年龄过滤检查:"
min_age_hours = SiteSetting.ai_replier_min_topic_age_hours
if min_age_hours > 0
  cutoff_time = min_age_hours.hours.ago
  age_filtered = quiet_topics.select { |t| t.created_at <= cutoff_time }
  puts "   年龄过滤后剩余主题数 (>=#{min_age_hours}小时): #{age_filtered.count}"
else
  puts "   年龄过滤: 已禁用"
end
puts

# 7. 模拟完整选择过程
puts "7. 完整选择过程模拟:"
selected = AiReplier::TopicSelector.select
puts "   最终选中的主题数: #{selected.count}"

if selected.any?
  puts "   选中的主题:"
  selected.each do |topic|
    cooldown_remaining = AiReplier::RateLimiter.cooldown_remaining(topic.id)
    puts "     - Topic ##{topic.id}: #{topic.title}"
    puts "       创建时间: #{topic.created_at}"
    puts "       帖子数: #{topic.posts_count}"
    puts "       浏览量: #{topic.views}"
    puts "       冷却期剩余: #{cooldown_remaining}秒"
  end
else
  puts "   ⚠️  没有选中任何主题"
end
puts

# 8. 提供建议
puts "8. 改进建议:"
puts

if ai_users.empty?
  puts "   🔧 创建AI用户: 需要创建邮箱以'fungps'开头的用户"
end

if rate_stats[:current_hour_count] >= rate_stats[:max_per_hour]
  puts "   🔧 速率限制: 当前小时已达到API调用限制，等待下一小时"
end

if cooldown_count > 0
  puts "   🔧 冷却期: 有 #{cooldown_count} 个主题在冷却期，考虑减少冷却时间"
end

if quiet_topics.count < 5
  puts "   🔧 主题选择: 符合条件的主题较少，考虑调整选择策略"
end

if selected.count == 0
  puts "   🔧 无选中主题: 检查主题选择条件是否过于严格"
end

puts
puts "=== 诊断完成 ==="
