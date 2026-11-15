# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Several wallets: add another under a name, switch between them, and remove one from
  omanero (its files are moved to `removed/`, never deleted). In Settings, and as
  `omanero wallets`, `create --name`, `restore --name`, `use` and `forget`.
- Plugins tab: tip the authors of installed Omarchy plugins whose `manifest.json` has
  `"funding": { "monero": "<address>" }`. Also `omanero plugins` in a terminal.

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

[Unreleased]: https://github.com/sette7blo/omanero/compare/v0.1.0...HEAD
[v0.1.0]: https://github.com/sette7blo/omanero/releases/tag/v0.1.0
