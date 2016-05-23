module.exports = () ->
  # ignore environments in these scopes
  ignoredScopes = ["comment", "markup.raw.verbatim"]
  te = atom.workspace.getActiveTextEditor()
  cursorEnv = ({cursor: cursor, stack: []} for cursor in te.getCursorBufferPositions())
  envRegex = /\\(begin|end)(?:\[[^\]]*\])?\{([^\}]*)\}/g
  te.scan(envRegex, (matchObj) ->
    match = matchObj.match
    name = match[2]
    isBegin = match[1] == "begin"
    # get the outer point of the environment
    envBorder = if isBegin then matchObj.range.start else matchObj.range.end
    # ignore comments
    descriptor = te.scopeDescriptorForBufferPosition(envBorder)
    if (descriptor.getScopesArray().some (d) -> (ignoredScopes.some (s) -> d.startsWith(s)))
      return
    # retrieve information about the match object
    endPoint = matchObj.range.end
    column = endPoint.column - 1
    range = [[endPoint.row, column - name.length], [endPoint.row, column]]

    cursorEnv.forEach (envObj) ->
      # if the environment is still before the cursor
      if envObj.cursor.isGreaterThan(envBorder)
        if isBegin
          # push opening environments on the stack
          envObj.stack.push([name, range])
        else
          # pop closing environments from the stack
          envObj.stack.pop()
      # if the environment is behind the cursor, but the end has not been found
      else if !envObj.end?
        # if we are the first time behind the cursor
        # pop and insert the last environment name
        if !envObj.begin?
          try
            [popName, popRange] = envObj.stack.pop()
          catch
            # if the stack was empty keep the cursor
            envObj.end = [envObj.cursor, envObj.cursor]
            atom.notifications.addWarning(
              "Cannot detect the surrounding environment for one cursor."
            )
            return
          envObj.begin = popRange
          envObj.beginName = popName
          # reset the environment stack
          envObj.stack = []

        if isBegin
          # push the opening environments on the stack
          envObj.stack.push(name)
        else if envObj.stack.length
          # if the are opening environments, pop them from the stack
          envObj.stack.pop()
        else
          if envObj.beginName != name
            atom.notifications.addWarning(
              "Environment '#{envObj.beginName}' and '#{name}' are not matching."
            )
            delete envObj.begin
            envObj.end = [envObj.cursor, envObj.cursor]
          else
            envObj.end = range

    # if every env has an end, we are done
    if (cursorEnv.every (x) -> x.end?)
      matchObj.stop()
  )
  # retrieve the selections
  sels = [].concat.apply([], ([x.begin, x.end] for x in cursorEnv))
  # filter undefined/invalid cursors (missing ends...)
  sels = sels.filter (x) -> x
  # set the selections in the
  te.setSelectedBufferRanges(sels)
  te.scrollToBufferPosition(sels[0][0]) if sels.length
