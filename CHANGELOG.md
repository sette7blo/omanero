# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [v0.5.5] - 2026-11-18

### Fixed
- `uninstall.sh` locks the wallet with the plugin's own `bin/omanero`, never with
  whatever is at `~/.local/bin/omanero`.
- The `monero:` link handler is registered only when `omanero.desktop` is the plugin's
  own launcher link, also with `--take-links`. When that name belongs to another
  launcher, setup leaves the handler alone and says so, and `uninstall.sh` leaves a
  handler entry naming it in place.

## [v0.5.4] - 2026-11-18

### Fixed
- The launcher (`omanero.desktop`) runs the plugin's own `bin/omanero` instead of `~/.local/bin/omanero`,
  which may belong to another program when the installer left it alone. Launchers written by earlier versions are rewritten on the next load.
  If the plugin folder's path holds characters a launcher cannot carry safely, no
  launcher is made.

## [v0.5.3] - 2026-11-18

### Fixed
- The installer no longer moves an existing `~/.local/bin/omanero` or `omanero.desktop` aside
  to put its own link there. A path that is already taken is left as it is, and the
  plugin works without the link. The uninstaller removes only links that point into the
  plugin. Backups made by earlier versions (`*.bak.<date>`) are not touched.

## [v0.5.2] - 2026-11-18

### Fixed
- Unlocking is about twice as fast. `monero-wallet-rpc` made itself a new TLS
  certificate for every connection, 4 to 12 seconds each on some machines. Its local
  port no longer uses TLS (it only listens on 127.0.0.1), and the node connection gets a
  certificate made by `openssl` in milliseconds, new at each unlock so the node cannot
  link two sessions by it. Without `openssl` it works as before.
- After unlocking, the panel no longer shows the password field again for a few seconds
  before the wallet appears.

## [v0.5.1] - 2026-11-16

### Security
- Nothing is sent to the wallet port until the system confirms that the other end of
  the connection belongs to you, and until it has proven it holds the session login.
  Another user on the same machine could take the port in the instant before
  `monero-wallet-rpc` bound it and be sent the seed and password of a wallet being
  restored, or the password of one being created or unlocked. Reported in the
  marketplace review.
- Locking the wallet takes a newly created seed off the screen even when "I wrote it
  down" was never pressed, whether it is locked from the bar, the panel, a terminal or
  by the idle timer. `omanero seed` shows it again after unlocking.

## [v0.5.0] - 2026-11-16

### Added
- The browser extension works on GitHub too. On a repo's front page it reads the address
  the repo publishes in `manifest.json` (`funding.monero`) or as a `monero:` link in
  `.github/FUNDING.yml`, fetched once a day at most from the repo on screen, and finds
  addresses in READMEs and profile bios. The Tip control sits beside the Releases
  heading, also for a repo whose only address is in its README. The panel names the
  repo and says when it is a fork.

## [v0.4.0] - 2026-11-16

### Added
- The header names the open wallet when there is more than one, and so do the bar
  tooltip and the unlock field. On stagenet the balance line says `Stagenet`.
- A wallet button in the header, or `W`, lists the wallets to switch to.
- Keys: `1` to `4` pick a tab, `Tab` and `h`/`l` step through them, `Shift+L` locks.

## [v0.3.0] - 2026-11-16

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

[Unreleased]: https://github.com/sette7blo/omanero/compare/v0.5.5...HEAD
[v0.5.5]: https://github.com/sette7blo/omanero/compare/v0.5.4...v0.5.5
[v0.5.4]: https://github.com/sette7blo/omanero/compare/v0.5.3...v0.5.4
[v0.5.3]: https://github.com/sette7blo/omanero/compare/v0.5.2...v0.5.3
[v0.5.2]: https://github.com/sette7blo/omanero/compare/v0.5.1...v0.5.2
[v0.5.1]: https://github.com/sette7blo/omanero/compare/v0.5.0...v0.5.1
[v0.5.0]: https://github.com/sette7blo/omanero/compare/v0.4.0...v0.5.0
[v0.4.0]: https://github.com/sette7blo/omanero/compare/v0.3.0...v0.4.0
[v0.3.0]: https://github.com/sette7blo/omanero/compare/v0.2.0...v0.3.0
[v0.2.0]: https://github.com/sette7blo/omanero/compare/v0.1.0...v0.2.0
[v0.1.0]: https://github.com/sette7blo/omanero/releases/tag/v0.1.0
