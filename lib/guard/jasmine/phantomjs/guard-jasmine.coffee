# This file is the script that runs within PhantomJS, requests the Jasmine specs
# and waits until they are ready.
phantom.injectJs 'lib/result.js'

# Set default values
options =
  url: phantom.args[0] || 'http://127.0.0.1:3000/jasmine'
  timeout: parseInt(phantom.args[1] || 10000)
  specdoc: phantom.args[2] || 'failure'
  focus: /true/i.test phantom.args[3]
  console: phantom.args[4] || 'failure'
  errors: phantom.args[5] || 'failure'

# Create the web page.
#
page = require('webpage').create()

# Used to collect log messages for later assignment to the spec
#
currentSpecId = -1
logs = {}
errors = {}

# Catch JavaScript errors
#
page.onError = (msg, trace) ->
  if currentSpecId
    errors[currentSpecId] ||= []
    errors[currentSpecId].push({ msg: msg, trace: trace })

# Capture console.log output to add it to
# the result when specs have finished.
#
page.onConsoleMessage = (msg, line, source) ->
  if /^RUNNER_END$/.test(msg)
    result = page.evaluate -> window.reporter.runnerResult
    console.log JSON.stringify(new Result(result, logs, errors, options).process())
    page.evaluate -> window.resultReceived = true

  else if /^SPEC_START: (\d+)$/.test(msg)
    currentSpecId = Number(RegExp.$1)

  else
    logs[currentSpecId] ||= []
    logs[currentSpecId].push(msg)

# Initialize the page before the JavaScript is run.
#
page.onInitialized = ->
  page.injectJs 'lib/console.js'
  page.injectJs 'lib/reporter.js'

  page.evaluate ->
    # Attach the console reporter when the document is ready.
    window.onload = ->
      window.onload = null
      window.resultReceived = false
      window.reporter = new ConsoleReporter()
      if window.jasmine
        jasmine.getEnv().addReporter(window.reporter)

# Open web page and run the Jasmine test runner
#
page.open options.url, (status) ->
  # Avoid that a failed iframe load breaks the runner, see https://github.com/netzpirat/guard-jasmine/pull/19
  page.onLoadFinished = ->
  if status isnt 'success'
    console.log JSON.stringify({ error: "Unable to access Jasmine specs at #{ options.url }" })
    phantom.exit()
  else
    waitFor jasmineReady, jasmineAvailable, options.timeout, jasmineMissing


# Test if the jasmine has been loaded
#
jasmineReady = ->
  page.evaluate -> window.jasmine

# Start specs after they are have been loaded
#
jasmineAvailable = ->
  waitFor specsReady, specsDone, options.timeout, specsTimedout

# Error message for when jasmine never loaded asynchronously
#
jasmineMissing = ->
  text = page.evaluate -> document.getElementsByTagName('body')[0]?.innerText

  if text
    error = """
            The Jasmine reporter is not available!

            #{ text }
            """
    console.log JSON.stringify({ error: error })
  else
    console.log JSON.stringify({ error: 'The Jasmine reporter is not available!' })

# Test if the specs have finished.
#
specsReady = ->
  page.evaluate -> window.resultReceived

# Error message for when specs time out
#
specsTimedout = ->
  text = page.evaluate -> document.getElementsByTagName('body')[0]?.innerText
  if text
    error = """
            Timeout waiting for the Jasmine test results!

            #{ text }
            """
    console.log JSON.stringify({ error: error })
  else
    console.log JSON.stringify({ error: 'Timeout for the Jasmine test results!' })

specsDone = ->
  phantom.exit()

# Wait until the test condition is true or a timeout occurs.
#
# @param [Function] test the test that returns true if condition is met
# @param [Function] ready the action when the condition is fulfilled
# @param [Number] timeout the max amount of time to wait in milliseconds
#
waitFor = (test, ready, timeout = 10000, timeoutFunction) ->
  start = Date.now()
  condition = false

  wait = ->
    if (Date.now() - start < timeout) and not condition
      condition = test()
    else
      clearInterval interval
      if condition
        ready()
      else
        timeoutFunction()
        phantom.exit(1)

  interval = setInterval wait, 250
