{CompositeDisposable, Range, Point} = require 'atom'

module.exports =

class DoubleTag
  constructor: (@editor) ->
    console.log 'new double tag'
    @subscriptions = new CompositeDisposable
    @cursor = null
    @frontOfStartTag = null
    @BackOfStartTag = null
    @startTagRange = null
    @tagText =  null
    @foundTag = false
    @startMarker = null
    @endMarker = null

  destroy: ->
    @subscriptions?.dispose()

  watchForTag: (event) ->
    console.log 'watching for tag'
    return if @editor.hasMultipleCursors() or @editorHasSelectedText()

    @cursor = event.cursor

    if @cursorInHtmlTag()
      console.log 'in tag'
      return unless @findStartTag()
      console.log @tagText

      @startMarker = @editor.markBufferRange(@startTagRange, {})

      return unless @findEndTag()
      console.log @endTagRange
      @endMarker = @editor.markBufferRange(@endTagRange, {})
      @foundTag = true

    return unless @foundTag

    # TODO: add to main/subscriptions
    @subscriptions.add @startMarker.onDidChange (event) =>
      @copyNewTagToEnd()
      console.log 'copied'

  copyNewTagToEnd: ->
    return if @editor.hasMultipleCursors() or @editorHasSelectedText()
    # console.log @startMarker.getBufferRange()
    newTag = @editor.getTextInBufferRange(@startMarker.getBufferRange())
    console.log 'new tag:', newTag
    console.log @endMarker.getBufferRange()
    @editor.setTextInBufferRange(@endMarker.getBufferRange(), newTag)
    @foundTag = false

  # private

  editorHasSelectedText: ->
    # TODO: add test for "undefined length for null"
    @editor.getSelectedText()?.length > 0

  cursorInHtmlTag: ->
    scopeDescriptor = @cursor?.getScopeDescriptor()
    return unless scopeDescriptor

    scopes = scopeDescriptor.getScopesArray()
    return unless scopes

    scopes[1]?.match(/(meta\.tag|incomplete\.html)/)

  setFrontOfStartTag: ->
    frontRegex = /<(a-z)?/i
    frontOfStartTag = @cursor.getBeginningOfCurrentWordBufferPosition(
      {wordRegex: frontRegex}
    )
    return unless frontOfStartTag

    # don't include <
    @frontOfStartTag = new Point(
      frontOfStartTag.row, frontOfStartTag.column + 1
    )

  setBackOfStartTag: ->
    row = @frontOfStartTag.row
    rowLength = @editor.buffer.lineLengthForRow(row)

    backRegex = /[>\s/]/
    scanRange = new Range(@frontOfStartTag, new Point(row, rowLength))
    backOfStartTag = null
    @editor.buffer.scanInRange backRegex, scanRange, (obj) ->
      backOfStartTag = obj.range.start
      obj.stop()
    @backOfStartTag = backOfStartTag

  cursorIsInStartTag: ->
    cursorPosition = @cursor.getBufferPosition()
    return unless @startTagRange.containsPoint(cursorPosition)
    return unless cursorPosition.isEqual(@backOfStartTag)
    true

  findStartTag: ->
    # TODO: don't allow #, in tag
    @setFrontOfStartTag()
    return unless @frontOfStartTag

    @setBackOfStartTag()
    return unless @backOfStartTag

    @startTagRange = new Range(@frontOfStartTag, @backOfStartTag)
    return unless @cursorIsInStartTag()

    @tagText = @editor.getTextInBufferRange(@startTagRange)
    true

  findEndTag: ->
    startTagRegex = new RegExp("<#{@tagText}[>\\s]", 'i')
    tagRegex = new RegExp("<\\/?#{@tagText}[>\\s]", 'gi')
    endTagRange = null
    nestedTagCount = 0
    scanRange = new Range(@backOfStartTag, @editor.buffer.getEndPosition())
    console.log tagRegex
    @editor.buffer.scanInRange tagRegex, scanRange, (obj) ->
      if obj.matchText.match(startTagRegex)
        nestedTagCount++
      else
        nestedTagCount--
      if nestedTagCount < 0
        endTagRange = obj.range
        obj.stop()
    console.log 'found end'
    return unless endTagRange
    @endTagRange = new Range(
      [endTagRange.start.row, endTagRange.start.column + 2],
      [endTagRange.end.row, endTagRange.end.column - 1]
    )

    true
