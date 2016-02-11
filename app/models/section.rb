# coding: utf-8
class Section < ActiveRecord::Base

  has_many :nodes, dependent: :destroy

  validates_presence_of :name
  validates_uniqueness_of :name


  default_scope -> { order(sort: :desc) }

  after_save :update_cache_version
  after_destroy :update_cache_version

  def update_cache_version
    # 记录节点变更时间，用于清除缓存
    CacheVersion.section_node_updated_at = Time.now.to_i
  end

  def sorted_nodes
    nodes.where("id NOT IN (?)", [Node.no_point_id]).sorted
  end

  def all_sorted_nodes
    self.nodes.sorted
  end

  def no_point_nodes
    # 被屏蔽的帖子在修改页面的所在节点里只需要显示屏蔽专区
    self.nodes.where(:_id => Node.no_point_id).sorted
  end
end
