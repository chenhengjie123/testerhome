# coding: utf-8
class Comment < ActiveRecord::Base
  include BaseModel
  include MarkdownBody

  belongs_to :commentable, polymorphic: true
  belongs_to :user

  validates_presence_of :body

  before_create :fix_commentable_id
  def fix_commentable_id
    self.commentable_id = self.commentable_id.to_i
  end

  after_create :increase_counter_cache
  def increase_counter_cache
    return if self.commentable.blank?
    self.commentable.inc(comments_count: 1)
  end

  before_destroy :decrease_counter_cache
  def decrease_counter_cache
    return if self.commentable.blank?
    self.commentable.inc(comments_count: -1)
  end

end
