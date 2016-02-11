# coding: utf-8
class Location < ActiveRecord::Base

  has_many :users

  scope :hot, -> { order(users_count: :desc) }

  validates_uniqueness_of :name, case_sensitive: false


  def self.find_by_name(name)
    return nil if name.blank?
    name = name.downcase.strip
    query = name.match(/\p{Han}/) != nil ? name : /#{name}/i
    self.where(name: query).first
  end

  def self.find_or_create_by_name(name)
    if not location = self.find_by_name(name)
      location = self.create(name: name.strip)
    end
    location
  end
end