# coding: utf-8
class Node < ActiveRecord::Base

  has_many :topics
  delegate :name, to: :section, prefix: true, allow_nil: true

  belongs_to :section


  validates_presence_of :name, :summary, :section
  validates_uniqueness_of :name

  # has_and_belongs_to_many :followers, class_name: 'User', inverse_of: :following_nodes

  scope :hots, -> { order(topics_count: :desc) }
  scope :sorted, -> { order(sort: :desc) }

  after_save :update_cache_version
  after_destroy :update_cache_version

  def update_cache_version
    # 记录节点变更时间，用于清除缓存
    CacheVersion.section_node_updated_at = Time.now
  end

  # 热门节点给 select 用的
  def self.node_collection
    Rails.cache.fetch("node:node_collection:#{CacheVersion.section_node_updated_at}") do
      Node.all.collect { |n| [n.name,n.id] }
    end
  end

  def self.jobs_id
    19
  end

  def self.bugs_id
    47
  end

  def self.no_point_id
      55
  end

  def self.opencourse_id
    67
  end

  # Markdown 转换过后的 HTML
  def summary_html
    Rails.cache.fetch("#{self.cache_key}/summary_html") do
      MarkdownConverter.convert(self.summary)
    end
  end

  # 是否为 jobs 节点
  def jobs?
    self.id == self.class.jobs_id
  end

  def bugs?
    self.id == self.class.bugs_id
  end

  def opencourses?
    self.id == self.class.opencourse_id
  end

  def self.new_topic_dropdowns
    return [] if SiteConfig.new_topic_dropdown_node_ids.blank?
    node_ids = SiteConfig.new_topic_dropdown_node_ids.split(',').uniq.take(5)
    where("id IN (?)", node_ids)
  end

end
