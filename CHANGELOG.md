# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- The Plugins tab is now **Authors** and also lists installed apps whose AppStream file
  carries `<custom><value key="Monero::address">...</value></custom>`. The README explains
  how app authors add it.

### Changed
- While a wallet is created, restored or unlocked, the form's fields are locked and the
  button shows the progress with moving dots, instead of a field that looks typeable.

## [v0.2.0] - 2026-11-15

### Added
- The browser extension lives in `extension/x/` so its `manifest.json` is not
  a second plugin manifest next to the Omarchy one.
- Installing is one command: `omarchy plugin add https://github.com/sette7blo/omanero.git --enable`.
  The first time the plugin loads it installs `monero-wallet-rpc`, `python3`,
  `qrencode`, and `wl-clipboard` if they are missing, then links the command,
  the `monero:` handler, and the X extension. A terminal opens only for the
  package password.
- Several wallets: add another under a name, switch between them, and remove one from
  omanero (its files are moved to `removed/`, never deleted). In Settings, and as
  `omanero wallets`, `create --name`, `restore --name`, `use` and `forget`.
- Plugins tab: tip the authors of installed Omarchy plugins whose `manifest.json` has
  `"funding": { "monero": "<address>" }`. Also `omanero plugins` in a terminal.

### Changed
- The plugin's own manifest names a Monero address for tips, and `LICENSE` names
  `sette7blo` as the copyright holder.

## [v0.1.0] - 2026-11-15

First release. Sending a payment end to end has not been tested yet: try stagenet or a
small amount first.

### Added
- Hot Monero wallet in the Omarchy bar that uses a remote node: no local node, no
  blockchain download.
- Create a wallet, or restore one from a 25-word seed and a restore height given as a
  block number or a date.
- Send with a review step that shows the real fee before anything is broadcast, receive
  with a copyable address, and a history of recent payments.
- Handler for `monero:` links: the panel opens with the address and amount filled in.
- Browser extension for X (`extension/`): a Tip control next to Monero addresses in bios
  and posts, the bar icon in the accent colour when the page in front has one, and
  "Tip @name" in the panel. People whose bio was seen with an address get an XMR badge
  next to their name in the feed and in follower lists.
- Settings for the node (Cake Wallet's three defaults or any other), mainnet or
  stagenet, and auto-lock after idle minutes.
- `omanero` command line tool and a launcher.
- Receive tab can show the address as a QR code (`omanero qr` in a terminal).

[Unreleased]: https://github.com/sette7blo/omanero/compare/v0.2.0...HEAD
[v0.2.0]: https://github.com/sette7blo/omanero/compare/v0.1.0...v0.2.0
[v0.1.0]: https://github.com/sette7blo/omanero/releases/tag/v0.1.0
