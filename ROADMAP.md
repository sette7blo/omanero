# Roadmap

## Where we are

First working version, on GitHub, not yet released. Checked on stagenet against a real
`monero-wallet-rpc` 0.18.5.4 on 2026-11-15: create, sync, lock, unlock, wrong password,
restore by date, address checks, review with no funds, history, link request, seed.
**Not yet checked: a real send** (needs stagenet coins) and the three mainnet nodes.

Tipping on X is omanero's own browser extension (`extension/`), decided 2026-11-15:
XMRadar was dropped as too heavy and as a separate thing that cannot light the bar icon.
Checked end to end in a headless Brave 157 against a fake X page (`tests/e2e/run.sh`),
and by hand on real X the same day: Tip controls, name badges, the lit bar icon and
"Tip @name" in the panel all showed. `install.sh` loads it through the browser flags file.

xmr.bio's signed directory was looked at on 2026-11-15 and left out: 110 entries, one
small operator, and it would be the extension's first network request.

## Next, in order

1. Get stagenet coins from a faucet into a stagenet wallet and send them: review, fee,
   relay, history, and the auto-lock afterwards.
2. Look at every panel view on screen and fix layout.
3. Create a mainnet wallet and confirm each of the three default nodes syncs it.
4. Release v0.1.0.

## Ideas, not scheduled

- Polyseed (16-word) restore.
- Subaddresses, one per tip jar.
- "Send everything" (sweep).
- Fiat value next to amounts.
- Tor or a SOCKS proxy for the node connection.
- Verified addresses and badges for people never visited: check handles against
  xmr.bio's signed directory. It would be the extension's first network request, so it
  needs an explicit decision.
- Check the address checksum in the extension, so a mistyped address gets no Tip control.
- Firefox build of the extension.
- An amount on the Receive QR code.
- Translations: move the panel strings into `i18n/en.json`.

## Standing constraints

- Hot wallet for small amounts. No feature that encourages keeping savings in it.
- Nothing is ever sent without the review screen and an explicit press. A `monero:` link
  only fills in the form.
- Seeds, passwords and the wallet service login never appear on a command line, in a
  log, or in the bar config. The seed is never copied to the clipboard.
- No balance on the bar.
- Uninstalling never deletes wallet files.
- No local node. The plugin stays light.
- The browser extension reads x.com and talks only to the wallet tool: no network
  requests, no keys, no wallet logic in the browser.
- Text from a link, a web page or the wallet service is untrusted: plain text in the UI,
  separate arguments in commands.
