# coding: utf-8
require "auto-space"

CORRECT_CHARS = [
  ['【', '['],
  ['】', ']'],
  ['（', '('],
  ['）', ')']
]

class Topic < ActiveRecord::Base
  include Redis::Objects
  include BaseModel

  # 临时存储检测用户是否读过的结果
  attr_accessor :read_state, :admin_editing, :admin_deleting

  belongs_to :user, inverse_of: :topics, counter_cache: true
  belongs_to :node, counter_cache: true
  belongs_to :last_reply_user, class_name: 'User'
  belongs_to :last_reply, class_name: 'Reply'
  has_many :replies, dependent: :destroy

  has_one :poll, dependent: :destroy

  validates_presence_of :user_id, :title, :body, :node

  counter :hits, default: 0

  delegate :login, to: :user, prefix: true, allow_nil: true
  delegate :body, to: :last_reply, prefix: true, allow_nil: true

  # scopes
  scope :last_actived, -> { order(last_active_mark: :desc) }
  # 推荐的话题
  scope :suggest, -> { where("suggested_at IS NOT NULL").order(suggested_at: :desc) }
  scope :without_suggest, -> { where(suggested_at: nil) }
  scope :high_likes, -> { order(likes_count: :desc).order(id: :desc) }
  scope :high_replies, -> { order(replies_count: :desc).order(id: :desc) }
  scope :no_reply, -> { where(replies_count: 0) }
  scope :popular, -> { where("likes_count > 5") }
  scope :exclude_column_ids, proc {|column, ids|
                             if ids.size == 0
                               all
                             else
                               where("#{column} NOT IN (?)", ids)
                             end
                           }
  scope :without_node_ids, proc { |ids| where("node_id NOT IN (?)" ,ids) }
  scope :excellent, -> { where("excellent >= 1") }

  scope :without_hide_nodes, -> { exclude_column_ids("node_id", Topic.topic_index_hide_node_ids) }
  scope :without_nodes, proc { |node_ids|
                        ids = node_ids + Topic.topic_index_hide_node_ids
                        ids.uniq!
                        exclude_column_ids("node_id", ids)
                      }
  scope :without_users, proc { |user_ids|
    exclude_column_ids("user_id", user_ids)
  }
  scope :without_body, -> { select(column_names - ['body'])}

  def self.fields_for_list
    columns = %w(body body_html who_deleted follower_ids)
    select(column_names - columns.map(&:to_s))
  end


  def self.find_by_message_id(message_id)
    where(message_id: message_id).first
  end

  def self.topic_index_hide_node_ids
    SiteConfig.node_ids_hide_in_topics_index.to_s.split(",").collect { |id| id.to_i }
  end

  before_save :store_cache_fields
  def store_cache_fields
    self.node_name = self.node.try(:name) || ""
  end
  before_save :auto_space_with_title
  def auto_space_with_title
    self.title.auto_space!
  end

  before_save :auto_correct_title
  def auto_correct_title
    CORRECT_CHARS.each do |chars|
      self.title.gsub!(chars[0], chars[1])
    end
    self.title.auto_space!
  end

  before_save do
    if self.admin_editing == true && self.node_id_changed?
      self.class.notify_topic_node_changed(self.id, self.node_id)
    end
  end

  before_destroy do
    if self.admin_deleting == true
      self.class.notify_topic_deleted(self.id)
    end
  end

  before_create :init_last_active_mark_on_create
  def init_last_active_mark_on_create
    self.last_active_mark = Time.now.to_i
  end

  after_create do
    NotifyTopicJob.perform_later(id)
  end

  def followed?(uid)
    follower_ids.include?(uid)
  end

  def push_follower(uid)
    return false if uid == user_id
    return false if followed?(uid)
    push(follower_ids: uid)
    true
  end

  def pull_follower(uid)
    return false if uid == user_id
    pull(follower_ids: uid)
    true
  end

  def update_last_reply(reply, opts = {})
    # replied_at 用于最新回复的排序，如果帖着创建时间在一个月以前，就不再往前面顶了
    return false if reply.blank? && !opts[:force]

    self.last_active_mark = Time.now.to_i if self.created_at > 3.months.ago
    self.replied_at = reply.try(:created_at)
    self.last_reply_id = reply.try(:id)
    self.last_reply_user_id = reply.try(:user_id)
    self.last_reply_user_login = reply.try(:user_login)
    self.save
  end

  # 更新最后更新人，当最后个回帖删除的时候
  def update_deleted_last_reply(deleted_reply)
    return false if deleted_reply.blank?
    return false if self.last_reply_user_id != deleted_reply.user_id

    previous_reply = self.replies.where("id NOT IN (?)", [deleted_reply.id]).recent.first
    self.update_last_reply(previous_reply, force: true)
  end

  # 删除并记录删除人
  def destroy_by(user)
    return false if user.blank?
    self.update_attribute(:who_deleted,user.login)
    self.destroy
  end

  def destroy
    super
    delete_notifiaction_mentions
  end

  def last_page_with_per_page(per_page)
    page = (self.replies_count.to_f / per_page).ceil
    page > 1 ? page : nil
  end

  # 所有的回复编号
  def reply_ids
    Rails.cache.fetch([self,"reply_ids"]) do
      replies.only(:id).map(&:id).sort
    end
  end

  def page_floor_of_reply(reply)
    reply_index = self.replies.unscoped.without_body.count
    [reply_index / Reply.per_page + 1, reply_index]
  end

  def excellent?
    self.excellent >= 1
  end

  def self.notify_topic_created(topic_id)
    topic = Topic.find_by_id(topic_id)
    return if topic.blank?

    notified_user_ids = topic.mentioned_user_ids

    follower_ids = (topic.user.try(:follower_ids) || [])
    follower_ids.uniq!

    # 给关注者发通知
    follower_ids.each do |uid|
      # 排除同一个回复过程中已经提醒过的人
      next if notified_user_ids.include?(uid)
      # 排除回帖人
      next if uid == topic.user_id
      puts "Post Notification to: #{uid}"
      Notification::Topic.create user_id: uid, topic_id: topic.id
    end
    true
  end

  def self.notify_topic_node_changed(topic_id, node_id)
    topic = Topic.find_by_id(topic_id)
    return if topic.blank?
    node = Node.find_by_id(node_id)
    return if node.blank?
    Notification::NodeChanged.create user_id: topic.user_id, topic_id: topic_id, node_id: node_id
    return true
  end

  def self.notify_topic_deleted(topic_id)
    topic = Topic.find_by_id(topic_id)
    return if topic.blank?
    Notification::TopicDeleted.create user_id: topic.user_id, topic_id: topic_id
    return true
  end

  def topic_pay_url
    self.user.qrcode_url
  end
end
