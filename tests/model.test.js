const test = require('node:test')
const assert = require('node:assert')
const Model = require('../Model.js')

// --- parsing -------------------------------------------------------------

test('parseSearch keeps well-formed rows and drops id-less ones', () => {
  const rows = Model.parseSearch(JSON.stringify({
    results: [
      { id: 'a', title: 'Solid', structure: 'Page', app: 'capacities://s/a' },
      { title: 'no id here' },
      { id: 'b' }
    ]
  }))
  assert.equal(rows.length, 2)
  assert.equal(rows[0].title, 'Solid')
  // A row with no title still renders, rather than showing an empty line.
  assert.equal(rows[1].title, 'Untitled')
})

test('parseSearch survives the CLI printing nothing at all', () => {
  assert.deepEqual(Model.parseSearch(''), [])
  assert.deepEqual(Model.parseSearch('not json'), [])
  assert.deepEqual(Model.parseSearch('{"results":"nope"}'), [])
})

test('parseStatus reports a missing token as not-connected', () => {
  const status = Model.parseStatus(JSON.stringify({
    queued: 3, token: false, error: 'No API token.', authRequired: true
  }))
  assert.equal(status.token, false)
  assert.equal(status.authRequired, true)
  assert.equal(status.queued, 3)
})

test('parseStatus reads the space title through the nested object', () => {
  const status = Model.parseStatus('{"token":true,"space":{"title":"liberato"},"queued":0}')
  assert.equal(status.space, 'liberato')
  assert.equal(status.token, true)
})

// --- selection -----------------------------------------------------------

test('clampIndex wraps in both directions', () => {
  assert.equal(Model.clampIndex(3, 3), 0)     // past the end comes back to the top
  assert.equal(Model.clampIndex(-1, 3), 2)    // Up from the first row reaches the last
  assert.equal(Model.clampIndex(1, 3), 1)
})

test('clampIndex is safe on an empty list', () => {
  assert.equal(Model.clampIndex(0, 0), 0)
  assert.equal(Model.clampIndex(5, 0), 0)
})

// --- text ----------------------------------------------------------------

test('elide only truncates what is too long', () => {
  assert.equal(Model.elide('short', 10), 'short')
  assert.equal(Model.elide('abcdefghij', 5), 'abcd…')
})

test('firstLine is what a multi-line capture is called in a toast', () => {
  assert.equal(Model.firstLine('  the thought  \nthe detail'), 'the thought')
  assert.equal(Model.lineCount('a\nb\nc'), 3)
})
