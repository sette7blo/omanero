// The Tip control both content scripts put on a page. One fixed look, Monero
// orange with white text, so it reads the same wherever it lands, in light and
// dark themes alike. Nothing is inherited from the page.

var OmaneroPill = (function () {
  function make(item, attribute, label, style, onPress) {
    var button = document.createElement("button")
    button.type = "button"
    button.setAttribute(attribute, item.address)
    button.textContent = label
    button.title = "Tip with the omanero wallet"
    button.style.cssText = "border:0;border-radius:9999px;background:#f26822;color:#fff;"
      + "-webkit-text-fill-color:#fff;font:inherit;font-weight:700;letter-spacing:normal;"
      + "text-transform:none;text-decoration:none;white-space:nowrap;cursor:pointer;flex:none;" + style
    button.addEventListener("click", function (event) {
      // The control often sits inside a link; the press must not also follow it.
      event.preventDefault()
      event.stopPropagation()
      onPress(item)
    })
    return button
  }

  var PILL_STYLE = "display:inline-block;margin:6px 0 0;padding:3px 12px;font-size:13px;line-height:18px"

  return { make: make, PILL_STYLE: PILL_STYLE }
})()
