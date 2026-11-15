# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Hot Monero wallet in the Omarchy bar that uses a remote node: no local node, no
  blockchain download.
- Create a wallet, or restore one from a 25-word seed and a restore height given as a
  block number or a date.
- Send with a review step that shows the real fee before anything is broadcast, receive
  with a copyable address, and a history of recent payments.
- Handler for `monero:` links: the panel opens with the address and amount filled in.
- Browser extension for X (`extension/`): a Tip control next to Monero addresses in bios
  and posts, the bar icon in the accent colour when the page in front has one, and "Tip @name" in
  the panel. People whose bio was seen with an address get an XMR badge next to their name
  in the feed and in follower lists.
- Settings for the node (Cake Wallet's three defaults or any other), mainnet or
  stagenet, and auto-lock after idle minutes.
- `omanero` command line tool and a launcher.
- Receive tab can show the address as a QR code (`omanero qr` in a terminal).

[Unreleased]: https://github.com/sette7blo/omanero/commits/main
