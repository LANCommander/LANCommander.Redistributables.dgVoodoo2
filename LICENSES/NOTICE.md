# Attribution and licensing

This repository contains two separately licensed things. Keeping them distinct
matters, because only one of them is ours to license.

## What we authored

The packaging scripts, workflows, option schema, curation overlay and
documentation in this repository are copyright (c) 2026 LANCommander and are
released under the MIT License, in `LICENSE`.

## What we redistribute

**Nothing.** This is the unusual case in the redistributable family: the published
`.LCX` contains no dgVoodoo files at all.

| | |
|---|---|
| Project | dgVoodoo 2 |
| Homepage | https://dege.freeweb.hu/dgVoodoo2/ |
| Copyright | (c) 2013-2026 Dege |
| License | Proprietary freeware, redistribution restricted |

The one upstream file this repository does keep is `Reference/dgVoodoo.conf`, the
plain-text configuration template. It is here because it is the only thing the
option schema can be generated from, and it is refreshed automatically when
upstream releases. No dgVoodoo binary is committed, packaged or published by us.

### Obligations we carry

dgVoodoo's terms are quoted verbatim in `UPSTREAM-LICENSE.txt`. Three clauses
shape this package:

- **"You cannot bundle dgVoodoo inside launchers or frameworks, for general use
  across multiple applications."** A LANCommander redistributable is precisely a
  launcher framework distributing one component across many games, so the payload
  is not bundled. `Source.Mode` is `none`.
- **"If you want to host or re-distribute dgVoodoo as a standalone component for
  any reason then you must provide the full .zip package."** `Scripts/Package.ps1`
  downloads the complete upstream archive and hands it over unmodified, including
  the control panel and the documentation shortcuts. This is the one place in the
  family where the payload is deliberately *not* narrowed to what a client needs.
- **"You can freely ship your game or game mod with individual dgVoodoo files
  included."** The install step copies the enabled DLLs into an individual game's
  directory, not into a shared or system location.

### Why this payload is distributed the way it is

The chain is: we publish scripts only; a LANCommander server running
`Scripts/Package.ps1` fetches the full archive from the author's own GitHub
releases; that server then serves its own LAN clients. At no point do we host,
mirror or republish dgVoodoo binaries.

This is enforced structurally rather than by care. `Resolve-RedistributablePayload`
returns no payload path in `none` mode however it is invoked, and `source.ps1`
extracts only `dgVoodoo.conf` and never a DLL.

---

If you are Dege and would prefer this package not exist, or want the approach
changed, please open an issue — we will act on it.
