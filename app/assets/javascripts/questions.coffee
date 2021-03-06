# QuestionsController 下所有页面的 JS 功能
window.Questions =
  question_id: null
  user_voted_answer_ids: []

window.QuestionView = Backbone.View.extend
  el: "body"
  currentPageImageURLs : []

  events:
    "click #answers .answer .btn-answer": "answer"
    "click .btn-focus-answer": "answer"
    "click #question-upload-image": "browseUpload"
    "click .insert-codes a": "appendCodesFromHint"
    "click a.at_floor": "clickAtFloor"
    "click a.follow": "follow"
    "click a.bookmark": "bookmark"
    "click .btn-move-page": "scrollPage"
    "click .question-detail a.qrcode": "testerhome_qrcode"
    "click .question-reward a.pay-qrcode": "testerhome_qrcode_pay"
    "click .notify-updated .update": "updateReplies"
    "click .pickup-emoji": "pickupEmoji"
    "click #node-selector .nodes .name a": "nodeSelectorNodeSelected"


  initialize: (opts) ->
    @parentView = opts.parentView

    @initComponents()
    @initDropzone()
    @initContentImageZoom()
    @initCloseWarning()
    @checkRepliesVoteStatus()
    @initReplyNotificationSubscribe()
    @resetClearReplyHightTimer()

  resetClearReplyHightTimer: ->
    clearTimeout(@clearHightTimer)
    @clearHightTimer = setTimeout ->
      $(".answer").removeClass("light")
    , 10000



  initDropzone: ->
    self = @
    editor = $("textarea.question-editor")
    editor.wrap "<div class=\"question-editor-dropzone\"></div>"

    editor_dropzone = $('.question-editor-dropzone')
    editor_dropzone.on 'paste', (event) =>
      self.handlePaste(event)

    dropzone = editor_dropzone.dropzone(
      url: "/photos"
      dictDefaultMessage: ""
      clickable: true
      paramName: "file"
      maxFilesize: 20
      uploadMultiple: false
      headers:
        "X-CSRF-Token": $("meta[name=\"csrf-token\"]").attr("content")
      previewContainer: false
      processing: ->
        $(".div-dropzone-alert").alert "close"
        self.showUploading()
      dragover: ->
        editor.addClass "div-dropzone-focus"
        return
      dragleave: ->
        editor.removeClass "div-dropzone-focus"
        return
      drop: ->
        editor.removeClass "div-dropzone-focus"
        editor.focus()
        return
      success: (header, res) ->
        self.appendImageFromUpload([res.url])
        return
      error: (temp, msg) ->
        App.alert(msg)
        return
      totaluploadprogress: (num) ->
        return
      sending: ->
        return
      queuecomplete: ->
        self.restoreUploaderStatus()
        return
    )

  uploadFile: (item, filename) ->
    self = @
    formData = new FormData()
    formData.append "file", item, filename
    $.ajax
      url: '/photos'
      type: "POST"
      data: formData
      dataType: "JSON"
      processData: false
      contentType: false
      beforeSend: ->
        self.showUploading()
      success: (e, status, res) ->
        self.appendImageFromUpload([res.responseJSON.url])
        self.restoreUploaderStatus()
      error: (res) ->
        App.alert("上传失败")
        self.restoreUploaderStatus()
      complete: ->
        self.restoreUploaderStatus()

  handlePaste: (e) ->
    self = @
    pasteEvent = e.originalEvent
    if pasteEvent.clipboardData and pasteEvent.clipboardData.items
      image = self.isImage(pasteEvent)
      if image
        e.preventDefault()
        self.uploadFile image.getAsFile(), "image.png"

  isImage: (data) ->
    i = 0
    while i < data.clipboardData.items.length
      item = data.clipboardData.items[i]
      if item.type.indexOf("image") isnt -1
        return item
      i++
    return false

  browseUpload: (e) ->
    $(".question-editor").focus()
    $('.question-editor-dropzone').click()
    return false

  showUploading: () ->
    $("#question-upload-image").hide()
    if $("#question-upload-image").parent().find("span.loading").length == 0
      $("#question-upload-image").before("<span class='loading'><i class='fa fa-circle-o-notch fa-spin'></i></span>")


  restoreUploaderStatus: ->
    $("#question-upload-image").parent().find("span.loading").remove()
    $("#question-upload-image").show()

  appendImageFromUpload : (srcs) ->
    src_merged = ""
    for src in srcs
      src_merged = "![](#{src})\n"
    @insertString(src_merged)
    return false

  # 回复
  answer: (e) ->
    if !App.isLogined()
      location.href = "/account/sign_in"
      return false
    _el = $(e.target)
    floor = _el.data("floor")
    login = _el.data("login")
    answer_body = $("#new_answer textarea")
    if floor
      new_text = "##{floor} @#{login} "
    else
      new_text = ''
    if answer_body.val().trim().length == 0
      new_text += ''
    else
      new_text = "\n#{new_text}"
    answer_body.focus().val(answer_body.val() + new_text)
    return false

  clickAtFloor: (e) ->
    floor = $(e.target).data('floor')
    @gotoFloor(floor)

  # 跳到指定楼。如果楼层在当前页，高亮该层，否则跳转到楼层所在页面并添
  # 加楼层的 anchor。返回楼层 DOM Element 的 jQuery 对象
  #
  # -   floor: 回复的楼层数，从1开始
  gotoFloor: (floor) ->
    answerEl = $("#answer#{floor}")
    @highlightReply(answerEl)
    answerEl

  # 高亮指定楼。取消其它楼的高亮
  #
  # -   answerEl: 需要高亮的 DOM Element，须要 jQuery 对象
  highlightReply: (answerEl) ->
    $("#answers .answer").removeClass("light")
    answerEl.addClass("light")

  # 异步更改用户 vote 过的回复的 vote 按钮的状态
  checkRepliesVoteStatus : () ->
    for id in Questions.user_voted_answer_ids
      el = $("#answers a.voteable[data-id=#{id}]")
      @parentView.voteableAsVoted(el)

  # Ajax 回复后的事件
  answerCallback : (success, msg) ->
    $("#main .alert-message").remove()
    if success
      $("abbr.timeago",$("#answers .answer").last()).timeago()
      $("abbr.timeago",$("#answers .total")).timeago()
      $("#new_answer textarea").val('')
      $("#preview").text('')
      App.notice(msg,'#answer')
    else
      App.alert(msg,'#answer')
    $("#new_answer textarea").focus()
    $('#answer-button').button('reset')

  # 图片点击增加全屏预览功能
  initContentImageZoom : () ->
    exceptClasses = ["emoji", "twemoji"]
    imgEls = $(".markdown img")
    for el in imgEls
      if exceptClasses.indexOf($(el).attr("class")) == -1
        $(el).wrap("<a href='#{$(el).attr("src")}' class='zoom-image' data-action='zoom'></a>")

    # Bind click event
    if App.mobile == true
      $('a.zoom-image').attr("target","_blank")
    else
      $('a.zoom-image').fluidbox
        overlayColor: "#FFF"
        closeTrigger: [ {
                    selector: 'window'
                    event: 'scroll'
                  } ]
    true

  preview: (body) ->
    $("#preview").text "Loading..."

    $.post "/questions/preview",
      "body": body,
      (data) ->
        $("#preview").html data.body
      "json"

  hookPreview: (switcher, textarea) ->
    # put div#preview after textarea
    self = @
    preview_box = $(document.createElement("div")).attr "id", "preview"
    preview_box.addClass("markdown form-control")
    $(textarea).after preview_box
    preview_box.hide()

    $(".edit a",switcher).click ->
      $(".wmd-panel").show();
      $(".preview",switcher).removeClass("active")
      $(this).parent().addClass("active")
      $(preview_box).hide()
      $(textarea).show()
      return false

    $(".preview a",switcher).click ->
      $(".wmd-panel").hide();
      $(".edit",switcher).removeClass("active")
      $(this).parent().addClass("active")
      $(preview_box).show()
      $(textarea).hide()
      self.preview($(textarea).val())
      return false

  initCloseWarning: () ->
    text = $("textarea.closewarning")
    return false if text.length == 0
    msg = "离开本页面将丢失未保存页面!" if !msg
    $("input[type=submit]").click ->
      $(window).unbind("beforeunload")
    text.change ->
      if text.val().length > 0
        $(window).bind "beforeunload", (e) ->
          if $.browser.msie
            e.returnValue = msg
          else
            return msg
      else
        $(window).unbind("beforeunload")

  testerhome_qrcode : (e) ->
    link = $(e.currentTarget)
    question_url = link.data("url")
    $('#qrcode-body').empty()
    $('#qrcode-body').qrcode(question_url)
    $('#qrcode-modal').modal
      keyboard : true
      backdrop : true
      show : true
    false

  testerhome_qrcode_pay : (e) ->
    $('#qrcode-pay-modal').modal
      keyboard : true
      backdrop : true
      show : true
    false

  bookmark : (e) ->
    target = $(e.currentTarget)
    question_id = target.data("id")
    link = $(".bookmark[data-id='#{question_id}']")

    if link.hasClass("active")
      $.ajax
        url : "/questions/#{question_id}/unfavorite"
        type : "DELETE"
      link.attr("title","收藏").removeClass("active")
    else
      $.post "/questions/#{question_id}/favorite"
      link.attr("title","取消收藏").addClass("active")
    false

  follow : (e) ->

    target = $(e.currentTarget)
    question_id = target.data("id")
    link = $(".follow[data-id='#{question_id}']")
    if link.hasClass("active")
      $.ajax
        url : "/questions/#{question_id}/unfollow"
        type : "DELETE"
      link.removeClass("active")
    else
      $.ajax
        url : "/questions/#{question_id}/follow"
        type : "POST"
      link.addClass("active")
    false

  submitTextArea : (e) ->
    if $(e.target).val().trim().length > 0
      $("form#new_answer").submit()
    return false

  # 往话题编辑器里面的光标前插入两个空白字符
  insertSpaces : (e) ->
    @insertString('  ')
    return false

  # 往话题编辑器里面插入代码模版
  appendCodesFromHint : (e) ->
    link = $(e.currentTarget)
    language = link.data("lang")
    txtBox = $(".question-editor")
    caret_pos = txtBox.caret('pos')
    prefix_break = ""
    if txtBox.val().length > 0
      prefix_break = "\n"
    src_merged = "#{prefix_break }```#{language}\n\n```\n"
    source = txtBox.val()
    before_text = source.slice(0, caret_pos)
    txtBox.val(before_text + src_merged + source.slice(caret_pos+1, source.count))
    txtBox.caret('pos',caret_pos + src_merged.length - 5)
    txtBox.focus()
    txtBox.trigger('click')
    return false

  insertString: (str) ->
    $target = $(".question-editor")
    start = $target[0].selectionStart
    end = $target[0].selectionEnd
    $target.val($target.val().substring(0, start) + str + $target.val().substring(end));
    $target[0].selectionStart = $target[0].selectionEnd = start + str.length
    $target.focus()


  scrollPage: (e) ->
    target = $(e.currentTarget)
    moveType = target.data('type')
    opts =
      scrollTop: 0
    if moveType == 'bottom'
      opts.scrollTop = $('body').height()
    $("body, html").animate(opts, 300)
    return false


  initComponents : ->
    $("textarea.question-editor").unbind "keydown.cr"
    $("textarea.question-editor").bind "keydown.cr", "ctrl+return", (el) =>
      return @submitTextArea(el)

    $("textarea.question-editor").unbind "keydown.mr"
    $("textarea.question-editor").bind "keydown.mr", "Meta+return", (el) =>
      return @submitTextArea(el)

    # 绑定文本框 tab 按键事件
    $("textarea.question-editor").unbind "keydown.tab"
    $("textarea.question-editor").bind "keydown.tab", "tab", (el) =>
      return @insertSpaces(el)

    $("textarea.question-editor").autogrow()

    # also highlight if hash is answer#
    matchResult = window.location.hash.match(/^#answer(\d+)$/)
    if matchResult?
      @highlightReply($("#answer#{matchResult[1]}"))

    @hookPreview($(".editor-toolbar"), $(".question-editor"))

    $("body").bind "keydown", "m", (el) ->
      $('#markdown_help_tip_modal').modal
        keyboard : true
        backdrop : true
        show : true

    # @ Mention complete
    App.atReplyable("textarea")

    # Focus title field in new-question page
    $("body[data-controller-name='questions'] #question_title").focus()

    # polls
    if $('body').data('controller-name') is 'questions'
      Poll.setup()

  initReplyNotificationSubscribe: () ->
    return if not App.access_token?
    return if App.access_token.length < 5
    console.log 'initReplyNotificationSubscribe'
    MessageBus.start()
    MessageBus.callbackInterval = 1000
    MessageBus.subscribe "/questions/" + Questions.question_id, (json) ->
      console.log 'receivedNotificationCount', json
      if json.user_id == App.current_user_id
        return false
      if json.action == 'create'
        if App.windowInActive
          @updateReplies()
        else
          $(".notify-updated").show()
    true

  updateReplies: () ->
    lastId = $("#answers .answer:last").data('id')
    if(!lastId)
      Turbolinks.visit(location.href)
      return false
    $.get "/questions/#{Questions.question_id}/answers.js?last_id=#{lastId}", =>
      $(".notify-updated").hide()
      $("#new_answer textarea").focus()
    false

  pickupEmoji: () ->
    if !window._emojiModal
      window._emojiModal = new EmojiModalView()
    window._emojiModal.show()
    false

  nodeSelectorNodeSelected: (e) ->
     el = $(e.currentTarget)
     e.preventDefault()
     $("#node-selector").modal('hide')
     nodeId = el.data('id')
     $('.form input[name="question[node_id]"]').val(nodeId)
     $('#node-selector-button').html(el.text())
     false