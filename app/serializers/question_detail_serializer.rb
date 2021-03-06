class QuestionDetailSerializer < QuestionSerializer
  attributes :body, :body_html, :hits, :likes_count, :suggested_at
  
  def hits
    object.hits.to_i
  end
end