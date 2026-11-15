const test = require("node:test")
const assert = require("node:assert/strict")
const D = require("../extension/x/detect.js")

const MAIN = "4A" + "b".repeat(93)
const SUB = "8B" + "c".repeat(93)
const STAGE = "59" + "d".repeat(93)

test("addresses are found only when they stand alone", () => {
  assert.deepEqual(D.findAddresses("tips: " + MAIN + " thanks"), [MAIN])
  assert.deepEqual(D.findAddresses("XMR:" + SUB + "\n" + STAGE + "."), [SUB, STAGE])
  assert.deepEqual(D.findAddresses(MAIN + " " + MAIN), [MAIN])
  assert.deepEqual(D.findAddresses("x" + MAIN), [])
  assert.deepEqual(D.findAddresses(MAIN + "b"), [])
  assert.deepEqual(D.findAddresses(MAIN.slice(0, 94)), [])
  assert.deepEqual(D.findAddresses("4Z" + "b".repeat(93)), [])
  assert.deepEqual(D.findAddresses("4A" + "0".repeat(93)), [])
  assert.deepEqual(D.findAddresses("bc1q" + "a".repeat(91)), [])
  assert.deepEqual(D.findAddresses(""), [])
  assert.deepEqual(D.findAddresses(null), [])
})

test("handles come from paths, pages do not", () => {
  assert.equal(D.handleFromPath("/ann_b"), "ann_b")
  assert.equal(D.handleFromPath("/ann_b/status/123?s=20"), "ann_b")
  assert.equal(D.handleFromPath("/home"), "")
  assert.equal(D.handleFromPath("/i/lists/1"), "")
  assert.equal(D.handleFromPath("/Search"), "")
  assert.equal(D.handleFromPath("/way_too_long_for_a_handle"), "")
  assert.equal(D.handleFromPath("/<b>"), "")
  assert.equal(D.handleFromPath(""), "")
})

test("people seen with an address are remembered", () => {
  const known = {}
  assert.equal(D.remember(known, "Ann_B", MAIN, 100), true)
  assert.equal(D.remember(known, "ann_b", MAIN, 200), false)
  assert.equal(D.lookup(known, "ANN_B"), MAIN)
  assert.equal(D.remember(known, "ann_b", SUB, 300), true)
  assert.equal(D.lookup(known, "ann_b"), SUB)
  assert.equal(D.remember(known, "<b>", MAIN, 1), false)
  assert.equal(D.remember(known, "bob", "nope", 1), false)
  assert.equal(D.lookup(known, "bob"), "")
  assert.equal(D.lookup({ bob: { address: "<img>" } }, "bob"), "")
  assert.equal(D.lookup({ bob: "x" }, "bob"), "")
  assert.equal(D.lookup(null, "bob"), "")
  assert.equal(D.forget(known, "Ann_B"), true)
  assert.equal(D.forget(known, "ann_b"), false)
  assert.equal(D.lookup(known, "ann_b"), "")
})

test("the oldest are dropped once the memory is full", () => {
  const known = {}
  for (let i = 0; i < D.MAX_KNOWN; i++) known["h" + i] = { address: MAIN, at: i + 10 }
  assert.equal(D.remember(known, "newest", SUB, 99999), true)
  assert.equal(Object.keys(known).length, D.MAX_KNOWN)
  assert.equal(D.lookup(known, "h0"), "")
  assert.equal(D.lookup(known, "h1"), MAIN)
  assert.equal(D.lookup(known, "newest"), SUB)
})

test("one entry per address, bio first, capped", () => {
  const items = [
    { address: MAIN, handle: "a", source: "post" },
    { address: SUB, handle: "b", source: "post" },
    { address: MAIN, handle: "c", source: "bio" }
  ]
  assert.deepEqual(D.unique(items), [items[2], items[1]])
  const many = Array.from({ length: 9 }, (_, i) => ({ address: "4A" + String(i + 1).repeat(93), handle: "h", source: "post" }))
  assert.equal(D.unique(many).length, 5)
  assert.deepEqual(D.unique(null), [])
})
