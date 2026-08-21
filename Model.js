// Pure helpers for the Capacities overlay. Everything here is free of QML
// types on purpose: it is where the parsing and index arithmetic live, so
// they can be tested with node (tests/model.test.js) instead of by opening
// the overlay and squinting.

// No .pragma library: the guarded module.exports at the bottom is what lets
// node require this file, and .pragma is a syntax error there.

function parseJson(raw, fallback) {
  if (!raw) return fallback
  try {
    var value = JSON.parse(String(raw))
    return value === null || value === undefined ? fallback : value
  } catch (error) {
    return fallback
  }
}

function parseSearch(raw) {
  var payload = parseJson(raw, {})
  var results = Array.isArray(payload.results) ? payload.results : []
  var rows = []
  for (var i = 0; i < results.length; i++) {
    var item = results[i] || {}
    if (!item.id) continue
    rows.push({
      id: String(item.id),
      title: String(item.title || "Untitled"),
      structure: String(item.structure || ""),
      app: String(item.app || ""),
      web: String(item.web || "")
    })
  }
  return rows
}

function parseStatus(raw) {
  var payload = parseJson(raw, {})
  var space = payload.space || {}
  return {
    token: payload.token === true,
    space: String(space.title || ""),
    queued: parseInt(payload.queued, 10) || 0,
    error: String(payload.error || ""),
    authRequired: payload.authRequired === true
  }
}

// The selection wraps, because a list you can only walk off the end of makes
// you press Up eleven times to reach the last row.
function clampIndex(index, count) {
  if (count <= 0) return 0
  var wrapped = index % count
  return wrapped < 0 ? wrapped + count : wrapped
}

function elide(text, limit) {
  var value = String(text || "")
  return value.length > limit ? value.slice(0, Math.max(0, limit - 1)) + "…" : value
}

// The first line is what a capture is "called" in a toast or a row; the rest
// is detail that has nowhere to go at that size.
function firstLine(text) {
  var value = String(text || "").split("\n")[0]
  return value.trim()
}

function lineCount(text) {
  return String(text || "").split("\n").length
}

// QML ignores this (module is undefined); node uses it to load the file.
if (typeof module !== "undefined") {
  module.exports = {
    parseJson: parseJson,
    parseSearch: parseSearch,
    parseStatus: parseStatus,
    clampIndex: clampIndex,
    elide: elide,
    firstLine: firstLine,
    lineCount: lineCount
  }
}
