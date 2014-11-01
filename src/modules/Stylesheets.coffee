# Find, parse, watch and transform stylesheets

class Stylesheets
  constructor: (@engine) ->
    @watchers = {}
    @sheets = {}

  initialize: [
    ['eval',  ['$attribute', ['$tag', 'style'], '*=', 'type', 'text/gss']]
    ['load',  ['$attribute', ['$tag', 'link' ], '*=', 'type', 'text/gss']]
  ]

  compile: ->
    @CleanupSelectorRegExp = new RegExp(@engine.Continuation.DESCEND, 'g')
    @engine.engine.solve 'Document', 'stylesheets', @initialize
    @inline = @engine.queries['style[type*="text/gss"]']
    @remote = @engine.queries['link[type*="text/gss"]']
    @collections = [@inline, @remote]


  getRule: (operation) ->
    rule = operation
    while rule = rule.parent
      if rule.name == 'rule'
        return rule
    return

  getStylesheet: (stylesheet) ->
    unless sheet = @sheets[stylesheet._gss_id]
      sheet = @sheets[stylesheet._gss_id]= document.createElement('STYLE')
      stylesheet.parentNode.insertBefore(sheet, stylesheet.nextSibling)
    return sheet

  getWatchers: (stylesheet) ->
    return @watchers[stylesheet._gss_id] ||= []

  getOperation: (operation, watchers, rule) ->
    needle = operation.sourceIndex
    for other in rule.properties
      if watchers[other]?.length
        needle = other
        break
    return needle

  # dump style into native stylesheet rule
  solve: (stylesheet, operation, continuation, element, property, value) ->
    if rule = @getRule(operation)
      if @watch operation, continuation, stylesheet
        if @update operation, property, value, stylesheet, rule
          @engine.engine.restyled = true

      return true

  update: (operation, property, value, stylesheet, rule) ->
    watchers = @getWatchers(stylesheet)
    dump = @getStylesheet(stylesheet)
    sheet = dump.sheet
    needle = @getOperation(operation, watchers, rule)
    previous = []

    for item, index in watchers
      break if index >= needle
      if ops = watchers[index]
        other = @getRule(watchers[ops[0]][0])
        if previous.indexOf(other) == -1
          previous.push(other)
    unless sheet
      if dump.parentNode
        dump.parentNode.removeChild(dump)
      return 
    rules = sheet.rules || sheet.cssRules
    

    if needle != operation.sourceIndex || value == ''
      generated = rules[previous.length]
      generated.style[property] = value

      next = undefined
      if needle == operation.sourceIndex
        needle++
      for index in [needle ... watchers.length]
        if ops = watchers[index]
          next = @getRule(watchers[ops[0]][0])
          if next != rule
            sheet.deleteRule(previous.length)
          break
      if !next
        sheet.deleteRule(previous.length)
    else
      body = property + ':' + value
      selectors = @getSelector(operation)
      index = sheet.insertRule(selectors + "{" + body + "}", previous.length)
    return true

  watch: (operation, continuation, stylesheet) ->
    watchers = @getWatchers(stylesheet)

    meta = (watchers[operation.sourceIndex] ||= [])
    if meta.indexOf(continuation) > -1
      return
    (watchers[continuation] ||= []).push(operation)
    return meta.push(continuation) == 1

  unwatch: (operation, continuation, stylesheet, watchers) ->
    watchers ?= @getWatchers(stylesheet)

    index = operation.sourceIndex

    meta = watchers[index]
    meta.splice meta.indexOf(continuation), 1

    observers = watchers[continuation]
    observers.splice observers.indexOf(operation), 1

    unless observers.length
      delete watchers[continuation]

    unless meta.length
      delete watchers[index]
      @update operation, operation[1], '', stylesheet, @getRule(operation)
  
  export: ->
    sheet = []
    for id, style of @sheets
      for rule in (style.sheet.rules || style.sheet.cssRules)
        text = rule.cssText.replace /\[matches~="(.*?)"\]/g, (m, selector) ->
          selector.replace(/@\d+/g, '').replace(/↓/g, ' ')
        sheet.push text

    return sheet.join('')

  remove: (continuation, stylesheets) ->
    if @collections
      for collection in @collections
        for stylesheet in collection
          if watchers = @getWatchers(stylesheet)
            if operations = watchers[continuation]
              for operation in operations by -1
                @unwatch(operation, continuation, stylesheet, watchers)
    return


  getSelector: (operation) ->
    return @getSelectors(operation).join(', ')

  getSelectors: (operation) ->
      parent = operation
      results = wrapped = custom = undefined

      # Iterate rules
      while parent

        # Append condition id to path
        if parent.name == 'if'
          if parent.uid
            if results
              for result, index in results
                if result.substring(0, 11) != '[matches~="'
                  result = @getCustomSelector(result)
                results[index] = result.substring(0, 11) + parent.uid + @engine.Continuation.DESCEND + result.substring(11)
        
        # Add rule selector to path
        else if parent.name == 'rule'
          selectors = parent[1].path

          if parent[1][0] == ','
            paths = parent[1].slice(1).map (item) -> 
              return !item.marked && item.groupped || item.path
          else
            paths = [parent[1].path]

          groups = parent[1].groupped && parent[1].groupped.split(',') ? paths

          # Prepend selectors with selectors of a parent rule
          if results?.length
            bits = selectors.split(',')

            update = []
            for result in results
              if result.substring(0, 11) == '[matches~="'
                update.push result.substring(0, 11) + selectors + @engine.Continuation.DESCEND + result.substring(11)
              else
                for bit, index in bits
                  if groups[index] != bit
                    update.push @getCustomSelector(selectors) + ' ' + result
                  else 
                    update.push bit + ' ' + result

            results = update
          # Return all selectors
          else 

            results = selectors.split(',').map (path, index) =>
              if path != groups[index]
                @getCustomSelector(selectors)
              else
                path
        parent = parent.parent

      for result, index in results
        results[index] = results[index].replace(@CleanupSelectorRegExp, '')
      return results

  getCustomSelector: (selector) ->
    return '[matches~="' + selector.replace(/\s+/, @engine.Continuation.DESCEND) + '"]'

module.exports = Stylesheets