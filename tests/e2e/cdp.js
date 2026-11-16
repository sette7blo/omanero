// Drives a headless browser over the DevTools protocol: serves a fake x.com
// page from memory (nothing goes to the real site) and reports what the
// extension did to it.
const port = process.argv[2]
const MAIN = "4A" + "b".repeat(93)
const SUB = "8B" + "c".repeat(93)
const PROFILE = `<!doctype html><html><body>
<div data-testid="UserDescription">Writer. Tips welcome: ${MAIN}</div>
<article data-testid="tweet"><div data-testid="User-Name"><a href="/bob_x">Bob</a></div>
<div data-testid="tweetText">my xmr ${SUB} thanks</div></article>
<article data-testid="tweet"><div data-testid="User-Name"><a href="/carol">Carol</a></div>
<div data-testid="tweetText">no address here</div></article>
</body></html>`
// A feed and a following list: nobody's address is in a post here.
const FEED = `<!doctype html><html><body>
<article data-testid="tweet"><div data-testid="User-Name"><a href="/Ann_B">Ann</a></div>
<div data-testid="tweetText">good morning</div></article>
<article data-testid="tweet"><div data-testid="User-Name"><a href="/bob_x">Bob</a></div>
<div data-testid="tweetText">hello</div></article>
<div data-testid="UserCell"><a href="/dave"><div><div dir="ltr">Dave</div></div></a>
<div>bio: ${SUB}</div></div>
<div data-testid="UserCell"><a href="/erin"><div><div dir="ltr">Erin</div></div></a><div>no address</div></div>
</body></html>`

// GitHub: a forked repo whose manifest.json names one address and whose README
// names another, and a profile with an address in its bio.
// A real address has 1 to 9, A or B as its second character.
const REPO_ADDR = "4B" + "d".repeat(93)
const GH_REPO = `<!doctype html><html><body>
<div id="repository-container-header"><strong>ann/plug</strong> <span>forked from bob/plug</span></div>
<div style="display:none"><h2>About</h2><p>A plugin, as narrow windows show it.</p></div>
<div class="Layout-sidebar"><h2>About</h2><p>A plugin.</p></div>
<div id="readme"><article class="markdown-body"><h1>plug</h1><p>Install it.</p>
<p>Tips: ${SUB}</p></article></div>
</body></html>`
// A repo with releases whose only address is in its README.
const GH_BARE = `<!doctype html><html><body>
<div id="repository-container-header"><strong>ann/bare</strong></div>
<div class="Layout-sidebar"><h2>About</h2><p>An app.</p><h2>Releases 3</h2></div>
<div id="readme"><article class="markdown-body"><h1>bare</h1>
<p>Donations:</p><pre>${SUB}</pre></article></div>
</body></html>`
const GH_PROFILE = `<!doctype html><html><body>
<div class="user-profile-bio"><div>Writes plugins. XMR ${MAIN}</div></div>
</body></html>`

const sleep = ms => new Promise(r => setTimeout(r, ms))

async function main() {
  const version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json()
  const ws = new WebSocket(version.webSocketDebuggerUrl)
  await new Promise((ok, bad) => { ws.onopen = ok; ws.onerror = bad })
  let next = 1
  const waiting = new Map()
  const handlers = []
  ws.onmessage = event => {
    const message = JSON.parse(event.data)
    if (message.id && waiting.has(message.id)) { waiting.get(message.id)(message); waiting.delete(message.id) }
    else handlers.forEach(h => h(message))
  }
  const call = (method, params, sessionId) => new Promise(resolve => {
    const id = next++
    waiting.set(id, m => resolve(m.result || { error: m.error }))
    ws.send(JSON.stringify({ id, method, params: params || {}, sessionId }))
  })

  if (process.argv[3] === "github") return github(call, handlers, evaluateIn)
  const { targetId } = await call("Target.createTarget", { url: "about:blank" })
  const { sessionId } = await call("Target.attachToTarget", { targetId, flatten: true })
  handlers.push(message => {
    if (message.method !== "Fetch.requestPaused" || message.sessionId !== sessionId) return
    const url = message.params.request.url
    if (url.startsWith("https://x.com/")) {
      call("Fetch.fulfillRequest", { requestId: message.params.requestId, responseCode: 200,
        responseHeaders: [{ name: "Content-Type", value: "text/html" }],
        body: Buffer.from(url.includes("/home") ? FEED : PROFILE).toString("base64") }, sessionId)
    } else {
      call("Fetch.failRequest", { requestId: message.params.requestId, errorReason: "BlockedByClient" }, sessionId)
    }
  })
  await call("Fetch.enable", { patterns: [{ urlPattern: "*" }] }, sessionId)
  await call("Page.enable", {}, sessionId)
  await call("Page.navigate", { url: "https://x.com/ann_b" }, sessionId)
  await sleep(4000)

  const evaluate = async expression =>
    (await call("Runtime.evaluate", { expression, returnByValue: true }, sessionId)).result.value
  console.log("url", await evaluate("location.href"))
  console.log("pills", await evaluate("JSON.stringify(Array.from(document.querySelectorAll('[data-omanero-tip]')).map(p => p.getAttribute('data-omanero-tip').slice(0, 6) + ' after ' + p.previousElementSibling.getAttribute('data-testid')))"))
  const targets = await call("Target.getTargets")
  console.log("extension targets", JSON.stringify(targets.targetInfos.filter(t => t.url.startsWith("chrome-extension://")).map(t => t.type + " " + t.url)))
  await call("Page.navigate", { url: "https://x.com/home" }, sessionId)
  await sleep(4000)
  console.log("badges", await evaluate("JSON.stringify(Array.from(document.querySelectorAll('[data-omanero-badge]')).map(b => b.getAttribute('data-omanero-badge').slice(0, 6) + ' in ' + (b.parentElement.getAttribute('data-testid') || b.closest('[data-testid]').getAttribute('data-testid'))))"))
  console.log("feed pills", await evaluate("document.querySelectorAll('[data-omanero-tip]').length"))
  if (process.argv[3] === "tip") {
    await evaluate("document.querySelector('[data-omanero-badge]').click()")
    await sleep(1500)
  }
  console.log("READY")
  // Stay up until told to stop, so the caller can read the wallet's status.
  process.stdin.on("data", async () => { await call("Browser.close"); process.exit(0) })
}
function evaluateIn(call, sessionId) {
  return async expression => (await call("Runtime.evaluate", { expression, returnByValue: true }, sessionId)).result.value
}

const PILLS = "JSON.stringify(Array.from(document.querySelectorAll('[data-omanero-tip]')).map(p => " +
  "p.getAttribute('data-omanero-tip').slice(0, 6) + (p.parentElement.tagName === 'H2' ? ' in ' + p.parentElement.firstChild.textContent.trim() : " +
  "' after ' + (p.previousElementSibling.id || p.previousElementSibling.className || p.previousElementSibling.tagName))))"

async function github(call, handlers, evaluateIn) {
  // The extension's own requests to raw.githubusercontent.com come from its
  // service worker, so they are answered there.
  const targets = await call("Target.getTargets")
  const worker = targets.targetInfos.find(t => t.type === "service_worker" && t.url.startsWith("chrome-extension://"))
  const asked = []
  if (worker) {
    const { sessionId: workerSession } = await call("Target.attachToTarget", { targetId: worker.targetId, flatten: true })
    handlers.push(message => {
      if (message.method !== "Fetch.requestPaused" || message.sessionId !== workerSession) return
      const url = message.params.request.url
      asked.push(url.replace("https://raw.githubusercontent.com/", ""))
      if (url.endsWith("/manifest.json") && !url.includes("/ann/bare/")) {
        call("Fetch.fulfillRequest", { requestId: message.params.requestId, responseCode: 200,
          responseHeaders: [{ name: "Content-Type", value: "text/plain" }],
          body: Buffer.from(JSON.stringify({ id: "x.plug", funding: { monero: REPO_ADDR } })).toString("base64") }, workerSession)
      } else {
        call("Fetch.fulfillRequest", { requestId: message.params.requestId, responseCode: 404,
          responseHeaders: [], body: "" }, workerSession)
      }
    })
    await call("Fetch.enable", { patterns: [{ urlPattern: "*raw.githubusercontent.com*" }] }, workerSession)
  }
  console.log("worker", worker ? "found" : "missing")

  const { targetId } = await call("Target.createTarget", { url: "about:blank" })
  const { sessionId } = await call("Target.attachToTarget", { targetId, flatten: true })
  handlers.push(message => {
    if (message.method !== "Fetch.requestPaused" || message.sessionId !== sessionId) return
    const url = message.params.request.url
    if (url.startsWith("https://github.com/")) {
      call("Fetch.fulfillRequest", { requestId: message.params.requestId, responseCode: 200,
        responseHeaders: [{ name: "Content-Type", value: "text/html" }],
        body: Buffer.from(url.endsWith("/ann/plug") ? GH_REPO : url.endsWith("/ann/bare") ? GH_BARE : GH_PROFILE).toString("base64") }, sessionId)
    } else {
      call("Fetch.failRequest", { requestId: message.params.requestId, errorReason: "BlockedByClient" }, sessionId)
    }
  })
  await call("Fetch.enable", { patterns: [{ urlPattern: "*" }] }, sessionId)
  await call("Page.enable", {}, sessionId)
  const evaluate = evaluateIn(call, sessionId)

  await call("Page.navigate", { url: "https://github.com/ann" }, sessionId)
  await sleep(3000)
  console.log("profile pills", await evaluate(PILLS))
  await call("Page.navigate", { url: "https://github.com/ann/bare" }, sessionId)
  await sleep(4000)
  console.log("readme-only repo pills", await evaluate(PILLS))
  await call("Page.navigate", { url: "https://github.com/ann/plug" }, sessionId)
  await sleep(4000)
  console.log("repo pills", await evaluate(PILLS))
  console.log("raw requests", JSON.stringify(asked))
  console.log("visible repo pills", await evaluate("Array.from(document.querySelectorAll('[data-omanero-tip]')).filter(p => p.getClientRects().length > 0).length"))
  await evaluate("Array.from(document.querySelectorAll('h2 + [data-omanero-tip], h2 > [data-omanero-tip]')).find(p => p.getClientRects().length > 0).click()")
  await sleep(1500)
  console.log("READY")
  process.stdin.on("data", async () => { await call("Browser.close"); process.exit(0) })
}

main().catch(error => { console.error("FAILED", error); process.exit(1) })
