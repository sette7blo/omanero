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
main().catch(error => { console.error("FAILED", error); process.exit(1) })
