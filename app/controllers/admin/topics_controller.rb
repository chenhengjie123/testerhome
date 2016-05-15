module Admin
  class TopicsController < ApplicationController

    before_action :add_modified_admin, only: [:destory, :undestory, :suggest, :unsuggest]

    def add_modified_admin
      @topic = Topic.unscoped.find(params[:id])
      @topic.update_attributes(modified_admin: current_user)
    end

    def index
      @topics = Topic.unscoped.desc(:_id).includes(:user).paginate page: params[:page], per_page: 30
    end

    def show
      @topic = Topic.unscoped.find(params[:id])
    end

    def new
      @topic = Topic.new
    end

    def edit
      @topic = Topic.unscoped.find(params[:id])
    end

    def create
      @topic = Topic.new(params[:topic].permit!)

      if @topic.save
        redirect_to(admin_topics_path, notice: 'Topic was successfully created.')
      else
        render action: 'new'
      end
    end

    def update
      @topic = Topic.unscoped.find(params[:id])

      if current_user.id != @topic.user_id
        # 管理员且非本帖作者
        @topic.modified_admin = current_user
      end

      if @topic.update_attributes(params[:topic].permit!)
        redirect_to(admin_topics_path, notice: 'Topic was successfully updated.')
      else
        render action: 'edit'
      end
    end

    def destroy
      @topic = Topic.unscoped.find(params[:id])
      @topic.destroy_by(current_user)
      @topic.update_attributes(modified_admin: current_user)
      redirect_to(admin_topics_path)
    end

    def undestroy
      begin
        @topic = Topic.unscoped.find(params[:id])
        @topic.update_attribute(:deleted_at, nil)
        @topic.update_attributes(modified_admin: current_user)
      rescue => e
        puts "do nothing"
      ensure
        @topic.__elasticsearch__.index_document
      end
      redirect_to(admin_topics_path)
    end

    def suggest
      @topic = Topic.unscoped.find(params[:id])
      @topic.update_attribute(:suggested_at, Time.now)
      @topic.update_attributes(modified_admin: current_user)
      CacheVersion.topic_last_suggested_at = Time.now
      redirect_to(admin_topics_path, notice: "Topic:#{params[:id]} suggested.")
    end

    def unsuggest
      @topic = Topic.unscoped.find(params[:id])
      @topic.update_attribute(:suggested_at, nil)
      @topic.update_attributes(modified_admin: current_user)
      CacheVersion.topic_last_suggested_at = Time.now
      redirect_to(admin_topics_path, notice: "Topic:#{params[:id]} unsuggested.")
    end
  end
end
