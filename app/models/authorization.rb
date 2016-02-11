# coding: utf-8
class Authorization < ActiveRecord::Base

  validates_presence_of :uid, :provider
  validates_uniqueness_of :uid, scope: :provider
end
