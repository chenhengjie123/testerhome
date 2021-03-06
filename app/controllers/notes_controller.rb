# coding: utf-8
class NotesController < ApplicationController
  before_action :require_user, except: [:show]
  load_and_authorize_resource

  def index
    @notes = current_user.notes.recent_updated.paginate(page: params[:page], per_page: 20)
    set_seo_meta t('menu.notes')
  end

  def show
    @note =  Note.find(params[:id])
    @note.hits.incr(1)
    set_seo_meta("查看 &raquo; #{t("menu.notes")}")
  end

  def new
    @note = current_user.notes.build
    set_seo_meta("新建 &raquo; #{t('menu.notes')}")
  end

  def edit
    @note = current_user.notes.find(params[:id])
    set_seo_meta("修改 &raquo; #{t('menu.notes')}")
  end

  def create
    @note = current_user.notes.new(note_params)
    @note.publish = note_params[:publish] == '1'
    if @note.save
      redirect_to(@note, notice: t('common.create_success'))
    else
      render action: 'new'
    end
  end

  def update
    @note = current_user.notes.find(params[:id])
    if @note.update_attributes(note_params)
      redirect_to(@note, notice: t('common.update_success'))
    else
      render action: 'edit'
    end
  end

  def preview
    render text: MarkdownTopicConverter.convert(params[:body])
  end

  def destroy
    @note = current_user.notes.find(params[:id])
    @note.destroy

    redirect_to(notes_url)
  end

  private

  def note_params
    params.require(:note).permit(:title, :body, :publish)
  end
end
