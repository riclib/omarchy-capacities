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

// ---- panel data ----------------------------------------------------------

// The shape bin/omarchy-capacities writes to data.json. Every field is
// defaulted: a panel that renders half a cache is better than one that throws
// on a sync that was interrupted mid-write.
function parseData(raw) {
  var d = parseJson(raw, {})
  var today = d.today || {}
  return {
    syncedAt: parseInt(d.syncedAt, 10) || 0,
    error: String(d.error || ""),
    authRequired: d.authRequired === true,
    space: String((d.space || {}).title || ""),
    noteId: String(today.id || ""),
    bullets: Array.isArray(today.bullets) ? today.bullets : [],
    tasks: Array.isArray(d.tasks) ? d.tasks : [],
    recent: Array.isArray(d.recent) ? d.recent : [],
    recentSkipped: Array.isArray(d.recentSkipped) ? d.recentSkipped : []
  }
}

// "3m", "4h", "2d" — a bar panel has no room for a date, and the age is the
// only part anyone reads at a glance.
function shortAge(iso, now) {
  if (!iso) return ""
  var then = Date.parse(iso)
  if (isNaN(then)) return ""
  var seconds = Math.max(0, ((now || Date.now()) - then) / 1000)
  if (seconds < 90) return "now"
  var minutes = seconds / 60
  if (minutes < 60) return Math.round(minutes) + "m"
  var hours = minutes / 60
  if (hours < 24) return Math.round(hours) + "h"
  var days = hours / 24
  if (days < 14) return Math.round(days) + "d"
  return Math.round(days / 7) + "w"
}

function syncedLabel(syncedAt, now) {
  if (!syncedAt) return "never synced"
  var age = shortAge(new Date(syncedAt * 1000).toISOString(), now)
  return age === "now" ? "just synced" : "synced " + age + " ago"
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
    lineCount: lineCount,
    parseData: parseData,
    shortAge: shortAge,
    syncedLabel: syncedLabel
  }
}
