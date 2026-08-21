# LANCommander.Redistributables.dgVoodoo2

Automatically built LANCommander redistributable import package (`.LCX`) for
[dgVoodoo 2](https://dege.freeweb.hu/dgVoodoo2/).

dgVoodoo 2 wraps Glide, DirectDraw and Direct3D 1-9 onto modern Direct3D 11/12, so
games written for 3Dfx Voodoo hardware or early DirectX run on current GPUs. It is
the usual fix for the black screens, palette corruption, broken alt-tab and
640x480 lock that late-90s and early-2000s titles hit on Windows 10 and 11.

Games that commonly want it at a LAN party: **Thief** and **Thief II**, **System
Shock 2**, **Grand Theft Auto III** and **Vice City**, **Need for Speed III** and
**High Stakes**, **Diablo II** (Glide), **Carmageddon 2**, **Interstate '76**,
**Homeworld**, **Giants: Citizen Kabuto** and **Sacrifice**.

## ⚠️ This package contains no dgVoodoo files

Read this before anything else, because it changes how you install it.

dgVoodoo 2 is proprietary freeware, and its
[terms](https://dege.freeweb.hu/dgVoodoo2/ReadmeGeneral/) say:

> You can freely ship your game or game mod with individual dgVoodoo files
> included. If you want to host or re-distribute dgVoodoo as a standalone component
> for any reason then you must provide the full .zip package. **You cannot bundle
> dgVoodoo inside launchers or frameworks, for general use across multiple
> applications**

A LANCommander redistributable is precisely a launcher framework distributing one
component across many games. So this repository publishes **scripts and an option
schema only**. We do not host, mirror or republish any dgVoodoo binary.

Instead, **your own server fetches the complete upstream archive**: the package
ships a `Package` script that downloads the full, unmodified `.zip` straight from
the author's GitHub releases onto your LANCommander server, which then serves its
own LAN clients. That satisfies the "full .zip package" clause and keeps the files
coming from Dege rather than from us.

The practical consequence: **after importing, run this redistributable's Package
script once** from the server's Redistributables page. Until you do, installing it
on a client fails with a message telling you exactly this. The scheduled package
job does it for you if you have one configured.

## Install it

Download the `.lcx` asset from the [latest release][latest] and import it through
your LANCommander server's **Redistributables** page, or from the CLI:

```
LANCommander.Launcher.CLI Import --Path LANCommander.Redistributables.dgVoodoo2-v<version>.lcx --Type Redistributable
```

Then:

1. Run the **Package** script once, so the server downloads dgVoodoo (see above).
2. Assign it to the games that need it.
3. For each game, open its **Redistributables** options and enable the APIs that
   game actually uses under **Deployment**. **Everything is off by default** — see
   the warning below.

Re-importing a newer release **updates** the existing entry rather than creating a
second one, because the identifiers in `redistributable.yml` are stable across
releases.

[latest]: https://github.com/LANCommander/LANCommander.Redistributables.dgVoodoo2/releases/latest

## Enable only what the game needs

dgVoodoo works by placing DLLs named after the system libraries they replace next
to the game executable. A `DDraw.dll` sitting beside a game that was talking to
DirectDraw perfectly well means dgVoodoo now intercepts an API that was not broken,
which is the single most common way to break a game with dgVoodoo.

So every API defaults to **off** and you opt in per game:

| Option | Places | Enable for |
|---|---|---|
| **Wrap DirectDraw** | `DDraw.dll`, `D3DImm.dll` | 2D games, and 3D games using Direct3D Immediate Mode (roughly DirectX 1-6). The usual fix for black screens and 8/16-bit colour failures. 32-bit only. |
| **Wrap Direct3D 8** | `D3D8.dll` | DirectX 8 games. 32-bit only. |
| **Wrap Direct3D 9** | `D3D9.dll` | DirectX 9 games. Only when there is a real problem — DirectX 9 still works natively. |
| **Wrap Glide (3Dfx)** | `Glide.dll`, `Glide2x.dll`, `Glide3x.dll` | Games whose best renderer was 3Dfx. Often looks and runs better than their software or Direct3D path. |

**Architecture** must match the game executable, not the operating system. Almost
every game old enough to need dgVoodoo is 32-bit. Note that upstream ships no
64-bit DirectDraw, Direct3D 8 or Direct3D Immediate Mode — no 64-bit game ever used
them — so on `x64` only Direct3D 9 and Glide can be deployed. Enabling the others
on `x64` logs a warning and deploys nothing.

## Options

The schema exposes **86 options**, mirroring dgVoodoo's own configuration file and
its control panel layout:

| Group | Options | |
|---|---|---|
| **Deployment** | 5 | Which libraries to install, and for which architecture. Not a dgVoodoo setting — this controls what is deployed at all. |
| **General** | 15 | Output backend, screen mode, image adjustment. Applies to every wrapped API. |
| **General (Advanced)** | 16 | Presentation, scaling and timing internals. Most games need none of these. |
| **Glide (3Dfx)** | 16 | Emulated Voodoo card, resolution, filtering and the period-accurate extras. |
| **Glide (Advanced)** | 3 | Dithering behaviour for Glide output. |
| **DirectX** | 16 | Emulated video card, VRAM, filtering, vsync and screen-mode handling. |
| **DirectX (Advanced)** | 15 | Resolution enumeration, dithering and buffer formats reported to the game. |

Everything is applied per game. Values resolve as schema default, then per-game
value, then per-action override.

Options are written into a `dgVoodoo.conf` generated next to the game executable
just before launch, and removed again when the game exits, so a game directory
never keeps stale forced settings.

`[Debug]` is not exposed — upstream states it affects only debug builds. A handful
of options upstream flags as dangerous are also excluded; the reasoning for each is
in `Schema.Overlay.yml`.

## What is in the package

| Path | |
|---|---|
| `Manifest.yml` | Redistributable metadata, including the embedded option schema |
| `Scripts/{guid}` | One entry per PowerShell script |

There is deliberately **no `Archives/` entry**. That absence is the licensing
posture, and it is checked on every build.

## How this repository works

| File | Purpose |
|---|---|
| `redistributable.yml` | Identity, source mode, config path, stable script GUIDs |
| `source.ps1` | Reports the upstream version and refreshes `Reference/dgVoodoo.conf`. Extracts nothing else, ever |
| `Parse-Config.ps1` | Reads dgVoodoo's section-level comment blocks into options, descriptions and choice lists |
| `Reference/dgVoodoo.conf` | Upstream's config template. The only input to the option schema, refreshed automatically |
| `Schema.Overlay.yml` | Hand-written curation: names, descriptions, the authored Deployment options, exclusions |
| `OptionSchema.yml` | Generated. Do not edit by hand |
| `Scripts/*.ps1` | Client-side and server-side scripts |
| `LICENSES/` | Upstream attribution and terms |

`OptionSchema.yml` is generated, and the build fails if the committed copy does not
match what the config produces. To regenerate it locally:

```powershell
Import-Module <path-to>/LANCommander.Redistributables/module/LANCommander.Redistributables
Invoke-RedistributableBuild -RepositoryPath . -UpdateSchema
```

Edit `Schema.Overlay.yml` to change how an option is presented; never edit
`OptionSchema.yml`, since the next rebuild overwrites it.

### Why there is a custom parser

dgVoodoo documents a whole section's options in one comment block sitting above a
blank line:

```ini
[Glide]

;  VideoCard:      "voodoo_graphics", "voodoo_rush", "voodoo_2", ...
;    TMUFiltering: "appdriven", "pointsampled", "bilinear"

VideoCard                           = voodoo_2
```

The shared INI parser ends a comment block at the first blank line, because
everywhere else a comment belongs to the key directly beneath it. That would drop
every description and every choice list here, so `Parse-Config.ps1` handles the
real layout instead. It recovers upstream's own documentation for 48 of the 94
keys and 24 choice lists, and keeps working when upstream adds more.

### Staying current

A scheduled workflow checks dege-diosg/dgVoodoo2 for new versions. When one
appears it refreshes `Reference/dgVoodoo.conf`, re-parses it, regenerates the
option schema through the overlay, and opens a pull request listing exactly which
options were added, removed or had their defaults change. Merging that pull request
publishes the release.

Options that upstream adds are picked up automatically and ship with whatever
documentation upstream gave them; the pull request calls them out so better prose
can be written.

## Licensing

The scripts, workflows, parser, option schema and documentation here are MIT
licensed. dgVoodoo 2 itself is not ours and is not redistributed by this project —
see [`LICENSES/NOTICE.md`](LICENSES/NOTICE.md) for the terms and for exactly how
the payload reaches a client.

If you are Dege and would prefer this package not exist, or want the approach
changed, please open an issue.
