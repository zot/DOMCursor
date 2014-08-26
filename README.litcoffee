DOMCursor
=========

Filtered cursoring on DOM trees.  DOMCursors can move forwards or backwards, by node or by character, with settable filters that can seamlessly skip over parts of the DOM.

This readme file is also the code.

Here are some examples (I'm wrapping them in a -> so I can get syntax highlighting in viewers that support it).

    ->

In Leisure, I use it like this, to retrieve text from the page (scroll down to see docs on these methods, by the way):

      DOMCursor.prototype.filterOrg = ->
        @addFilter (n)-> !n.hasAttribute('data-nonorg') || 'skip'

      domCursor = (node, pos)-> new DOMCursor(node, pos).filterOrg()

      # full text for node
      getOrgText = (node)->
        domCursor node.firstChild, 0
          .mutable()
          .filterTextNodes()
          .filterParent node
          .getText()

And like this for cursor movement.  Once I have the cursor, I can use forwardChar, backwardChar, forwardLine, backwardLine to move it around:

      domCursorForCaret = ->
        sel = getSelection()
        parent = parentForNode sel.focusNode
        n = domCursor sel.focusNode, sel.focusOffset
          .mutable()
          .filterVisibleTextNodes()
          .filterParent parent
          .firstText()
        if n.pos < n.node.length then n else n.next()

DOMCursor Class
---------------

DOMCursors are immutable -- operations on them return new DOMCursers.
There are two ways to get mutabile cursors, sending @mutable() or
sending @withMutations (m)-> ...

A DOMCursor has a node, a position, a filter, and a type.

- node: like with ranges, a DOM node
- position: like with ranges, either the index of a child, for elements, or the index of a character, for text nodes.
- filter: a function used by @next() and @prev() to skip over portions of DOM. It returns
  - truthy: to accept a node but its children are still filtered
  - falsey: to reject a node but its children are still filtered
  - 'skip': to skip a node and its children
  - 'quit': to end to make @next() or @prev() return an empty DOMCursor
- type: 'empty', 'text', or 'element'

The class...

    class DOMCursor
      constructor: (@node, @pos, filter)->
        @pos = @pos ? 0
        @filter = filter || -> true
        @computeType()
      computeType: ->
        @type = if !@node then 'empty'
        else if @node.nodeType == Node.TEXT_NODE then 'text'
        else 'element'
        this
      newPos: (node, pos)-> new DOMCursor node, pos, @filter

**isEmpty** returns true if the cursor is empty

      isEmpty: -> @type == 'empty'

**setFilter** sets the filter

      setFilter: (f)-> new DOMCursor @node, @pos, f

**addFilter** adds a filter

      addFilter: (filt)->
        oldFilt = @filter
        @setFilter (n)->
          (((r1 = oldFilt n) in ['quit', 'skip']) && r1) || (((r2 = filt n) in ['quit', 'skip']) && r2) || (r1 && r2)

**next** moves to the next filtered node

      next: (up)->
        saved = @save()
        n = @nodeAfter up
        while !n.isEmpty()
          switch res = @filter n
            when 'skip'
              n = n.nodeAfter true
              continue
            when 'quit' then break
            else
              if res then return n
          n = n.nodeAfter()
        @restore(saved).emptyNext()

**prev** moves to the next filtered node

      prev: (up)->
        saved = @save()
        n = @nodeBefore up
        while !n.isEmpty()
          switch res = @filter n
            when 'skip'
              n = n.nodeBefore true
              continue
            when 'quit' then break
            else
              if res then return n
          n = n.nodeBefore()
        @restore(saved).emptyPrev()

**moveCaret** move the document selection to the current position

      moveCaret: (r)->
        if !r then r = document.createRange()
        r.setStart @node, @pos
        r.collapse true
        selectRange r
        this

**firstText** find the first text node (the 'backwards' argument is optional and if true,
indicates to find the first text node behind the cursor).

      firstText: (backwards)->
        n = this
        while !n.isEmpty() && n.type != 'text'
          n = (if backwards then n.prev() else n.next())
        n

**countChars** count the characters in the filtered nodes until we get to (node, pos)

Include (node, 0) up to but not including (node, pos)

      countChars: (node, pos)->
        tot = 0
        while !n.isEmpty() && n.node != node
          if n.type == 'text' then tot += n.node.length
          n = n.next()
        if n.isEmpty() || n.node != node then -1
        else if n.type == 'text' then tot + pos
        else tot

**forwardChars** moves the cursor forward by count characters

if contain is true and the final location is 0 then go to the end of
the previous text node (node, node.length)

      forwardChars: (count, contain)->
        n = this
        while !n.isEmpty() && 0 <= count
          if n.type == 'text'
            if count < n.node.length
              if count == 0 && contain
                n = n.prev()
                while n.type != 'text' then n = n.prev()
                return n.newPos n.node, n.node.length
              else return n.newPos n.node, count
            count -= n.node.length
          n = n.next()
        n.emptyNext()

**hasAttribute** returns true if the node is an element and has the attribute

      hasAttribute: (a)-> @node?.nodeType == Node.ELEMENT_NODE && @node.hasAttribute a

**getAttribute** returns the attribute if the node is an element and has the attribute

      getAttribute: (a)-> @node?.nodeType == Node.ELEMENT_NODE && @node.getAttribute a

**filterTextNodes** adds text node filtering to the current filter; the cursor will only find text nodes

      filterTextNodes: -> @addFilter (n)-> n.type == 'text'

**filterTextNodes** adds visible text node filtering to the current filter; the cursor will only find visible text nodes

      filterVisibleTextNodes: -> @filterTextNodes().addFilter (n)-> !isCollapsed n.node

**filterParent** adds parent filtering to the current filter; the cursor will only find nodes that are contained in the parent (or equal to it)

      filterParent: (parent)->
        if !parent then @setFilter -> 'quit'
        else @addFilter (n)-> parent.contains(n.node) || 'quit'

**filterRange** adds range filtering to the current filter; the cursor will only find nodes that are contained in the range

      filterRange: (startContainer, startOffset, endContainer, endOffset)->
        if !startOffset?
          if startContainer instanceof Range
            r = startContainer
            startContainer = r.startContainer
            startOffset = r.startOffset
            endContainer = r.endContainer
            endOffset = r.endOffset
          else return this
        @addFilter (n)->
          startPos = startContainer.compareDocumentPosition n.node
          (if startPos == 0 then startOffset <= n.pos <= endOffset
          else if startPos & Node.DOCUMENT_POSITION_FOLLOWING
            endPos = endContainer.compareDocumentPosition n.node
            if endPos == 0 then n.pos <= endOffset
            else endPos & Node.DOCUMENT_POSITION_PRECEDING) || 'quit'

**getText** gets all of the text at or after the cursor (useful with filtering; see above)

      getText: ->
        n = @mutable().firstText()
        if n.isEmpty() then ''
        else
          t = n.node.data.substring n.pos
          while !n.next().isEmpty()
            if n.type == 'text' then t += n.node.data.substring n.pos
          if t.length
            while n.type != 'text'
              n.prev()
            n.pos = n.node.length
            while n.pos > 0 && reject n.filter n
              n.pos--
            t.substring 0, t.length - n.node.length + n.pos
          else ''

**isNL** returns whether the current character is a newline

      isNL: -> @type == 'text' && @node.data[@pos] == '\n'

**endsInNL** returns whether the current node ends with a newline

      endsInNL: -> @type == 'text' && @node.data[@node.length - 1] == '\n'

**moveToStart** moves to the beginning of the node

      moveToStart: -> @newPos @node, 0

**moveToNextStart** moves to the beginning of the next node

      moveToNextStart: -> @next().moveToStart()

**moveToEnd** moves to the textual end the node (1 before the end if the node
ends in a newline)

      moveToEnd: ->
        end = @node.length - (if @endsInNL() then 1 else 0)
        @newPos @node, end

**moveToPrevEnd** moves to the textual end the previous node (1 before
the end if the node ends in a newline)

      moveToPrevEnd: -> @prev().moveToEnd()

**forwardLine** moves to the next line, trying to keep the current screen pixel column.  Optionally takes a goalFunc that takes the position's screen pixel column as input and returns -1, 0, or 1 from comparing the input to the an goal column

      forwardLine: (goalFunc)->
        if !goalFunc then goalFunc = -> -1
        r = @charRect()
        bottom = r.bottom
        line = 0
        n = this
        while n = n.forwardChar()
          if n.isEmpty() then return n.backwardChar()
          r = n.charRect()
          if r.bottom != bottom
            bottom = r.bottom
            line++
          if line == 1 && goalFunc(r.left) > -1 then return n
          if line == 2 then return n.backwardChar()

**backwardLine** moves to the previous line, trying to keep the current screen pixel column.  Optionally takes a goalFunc that takes the position's screen pixel column as input and returns -1, 0, or 1 from comparing the input to an internal goal column

      backwardLine: (goalFunc)->
        # optional goalFunc takes the position's screen pixel column as input
        # It returns -1, 0, or 1, comparing the input to the internal goal column
        if !goalFunc then goalFunc = -> -1
        r = @charRect()
        prevTop = top = r.top
        line = 0
        n = this
        while n = n.backwardChar()
          if n.isEmpty() then return n.forwardChar()
          r = n.charRect()
          if r.top != top
            top = r.top
            line++
          if line == 1
            switch goalFunc r.left
              when 0 then return n
              when -1 then return (if prevTop == top then n.forwardChar() else n)
          if line == 2 then return n.forwardChar()
          prevTop = top

**forwardChar** move forward by one character (using the filter)

      forwardChar: ->
        r = stubbornCharRectNext(@node, @pos)
        left = r?.left
        bottom = r?.bottom
        n = this
        while n = (if n.pos + 1 < n.node.length then n.newPos n.node, n.pos + 1 else n.next())
          if n.isEmpty() || ((r = stubbornCharRectNext(n.node, n.pos)) && (left != r?.left || bottom != r?.bottom)) then return n

**backwardChar** move backward by one character (using the filter)

      backwardChar: ->
        r = stubbornCharRectPrev @node, @pos
        n = this
        while r && n = (if n.pos > 0 then n.newPos n.node, n.pos  - 1 else n.prev())
          if n.isEmpty() || n.moved(r) then return n
        n

**show** scroll the position into view.  Optionally takes a rectangle representing a toolbar at the top of the page (sorry, this is a bit limited at the moment)

      show: (topRect)->
        posRect = @charRect()
        top = if topRect?.width && topRect.top == 0 then topRect.bottom else 0
        if posRect.bottom > window.innerHeight then window.scrollBy 0, posRect.bottom - window.innerHeight
        else if posRect.top < top then window.scrollBy 0, posRect.top - top
        this

**immutable** return an immutable version of this cursor

      immutable: -> this

**withMutations** call a function with a mutable version of this cursor

      withMutations: (func)-> func @copy().mutable()

**mutable** return a mutable version of this cursor

      mutable: -> new MutableDOMCursor @node, @pos, @filter

**save** generate a memento which can be used to restore the state (used by mutable cursors)

      save: -> this

**restore** restore the state from a memento (used by mutable cursors)

      restore: (n)-> n.immutable()

**copy** return a copy of this cursor

      copy: -> this

**nodeAfter** low level method that moves to the unfiltered node after the current one

      nodeAfter: (up)->
        node = @node
        while node
          if node.nodeType == Node.ELEMENT_NODE && !up && node.childNodes.length
            return @newPos node.childNodes[0], 0
          else if node.nextSibling
            return @newPos node.nextSibling, 0
          else
            up = true
            node = node.parentNode
        @emptyNext()

**emptyNext** returns an empty cursor whose prev is the current node

      emptyNext: ->
        # return an empty next node where
        #   prev returns this node
        #   next returns the same empty node
        __proto__: emptyDOMCursor
        filter: @filter
        prev: (up)=> if up then @prev up else this
        nodeBefore: (up)=> if up then @nodeBefore up else this

**nodeBefore** low level method that moves to the unfiltered node before the current one

      nodeBefore: (up)->
        node = @node
        while node
          if node.nodeType == Node.ELEMENT_NODE && !up && node.childNodes.length
            newNode = node.childNodes[node.childNodes.length - 1]
          else if node.previousSibling then newNode = node.previousSibling
          else
            up = true
            node = node.parentNode
            continue
          return @newPos newNode, newNode.length
        @emptyPrev()

**emptyPrev** returns an empty cursor whose next is the current node

      emptyPrev: ->
        # return an empty prev node where
        #   next returns this node
        #   prev returns the same empty node
        __proto__: emptyDOMCursor
        filter: @filter
        next: (up)=> if up then @next up else this
        nodeAfter: (up)=> if up then @nodeAfter up else this

**moved** return whether a rectangle is at a different position than the current character

      moved: (rec)->
        (@node.length > @pos) && (r2 = stubbornCharRectPrev @node, @pos) && (rec.top != r2.top || rec.left != r2.left)
      charRect: (r, prev)->
        if prev
          stubbornCharRectPrev(@node, @pos, r) || stubbornCharRectNext(@node, @pos, r)
        else stubbornCharRect @node, @pos, r

EmptyDOMCursor Class
--------------------

An empty cursor

    class EmptyDOMCursor extends DOMCursor
      moveCaret: -> this
      show: -> this
      nodeAfter: -> this
      nodeBefore: -> this
      next: -> this
      prev: -> this

    #singleton empty node cursor
    emptyDOMCursor = new EmptyDOMCursor()

MutableDOMCursor Class
----------------------

A mutable cursor -- cursor movement, filter changes, etc. change the cursor instead of returning a new one.

    class MutableDOMCursor extends DOMCursor
      constructor: (@node, @pos, @filter)-> super node, pos, filter
      setFilter: (f)->
        @filter = f
        this
      newPos: (@node, @pos)-> @computeType()
      copy: -> new MutableDOMCursor @node, @pos, @filter
      mutable: -> this
      immutable: -> new DOMCursor @node, @pos, @filter
      save: -> new DOMCursor @node, @pos, @filter
      restore: (np)->
        @node = np.node
        @pos = np.pos
        @filter = np.filter
        this
      emptyPrev: ->
        @type = 'empty'
        @next = (up)->
          @revertEmpty()
          if up then @next up else this
        @nodeAfter = (up)->
          @computeType()
          if up then @nodeAfter up else this
        @prev = -> this
        @nodeBefore = -> this
        this
      revertEmpty: ->
        @computeType()
        delete @next
        delete @prev
        delete @nodeAfter
        delete @nodeBefore
        this
      emptyNext: ->
        @type = 'empty'
        @prev = (up)->
          @revertEmpty()
          if up then @prev up else this
        @nodeBefore = (up)->
          @computeType()
          if up then @nodeBefore up else this
        @next = -> this
        @nodeAfter = -> this
        this

Utility functions
-----------------

These are available as properties on DOMCursor.

    # Thanks to rangy for this: https://github.com/timdown/rangy
    isCollapsed = (node)->
      if node
        type = node.nodeType
        type == 7 || # PROCESSING_INSTRUCTION
        type == 8 || # COMMENT
        (type == Node.TEXT_NODE && (node.data == '' || isCollapsed(node.parentNode))) ||
        /^(script|style)$/i.test(node.nodeName) ||
        #(type == Node.ELEMENT_NODE && (node.offsetWidth == 0 || node.offsetHeight == 0))
        (type == Node.ELEMENT_NODE && node.offsetHeight == 0)
      else false

    selectRange = (r)->
      sel = getSelection()
      sel.removeAllRanges()
      sel.addRange r

    reject = (filterResult)-> !filterResult || (filterResult in ['quit', 'skip'])

    # charRect returns null for newlines when not using pre
    stubbornCharRect = (node, pos, r)->
      stubbornCharRectNext(node, pos, r) || stubbornCharRectPrev(node, pos, r)

    stubbornCharRectNext = (node, pos, r)->
      r = r || document.createRange()
      for i in [pos ... node.length] by 1
        if rec = charRect node, i, r then return rec
      null

    stubbornCharRectPrev = (node, pos, r)->
      r = r || document.createRange()
      for i in [pos .. 0] by -1
        if rec = charRect node, i, r then return rec
      null

    charRect = (node, pos, r)->
      r = r || document.createRange()
      r.setStart node, pos
      r.collapse true
      _(r.getClientRects()).last()

    DOMCursor.MutableDOMCursor = MutableDOMCursor
    DOMCursor.emptyDOMCursor = emptyDOMCursor
    DOMCursor.isCollapsed = isCollapsed
    DOMCursor.selectRange = selectRange

    @DOMCursor = DOMCursor
