# Manifold license

Copyright (c) 2026 Michael Bickford ("Woflo"), publishing as Woflo Labs.

Permission is granted to copy and distribute this Work Notice verbatim with
Manifold. A modified Work Notice may accompany a permitted modified version of
Manifold, but it must accurately identify the licenses and applicable notices
and must not imply endorsement by Michael Bickford or Woflo Labs.

Manifold is built in public, but not every part of it is released under the
same terms. Most of the project is GPL; the reusable Woflo research components
listed below use the Woflo Labs Community Source License. This file is the
controlling Work Notice and the exact boundary between them.

**Work:** Manifold, including the original source code, documentation, tests,
fixtures, assets, and Woflo research components in this repository.

**Repository:** `https://github.com/worflor/git-desktop-premium-ultra-promax-plus-R`

**Licensor:** Michael Bickford ("Woflo"), publishing as Woflo Labs.

## Most of Manifold: GPL-3.0-or-later

Unless a path is listed in the next section or carries its own third-party
notice, original material in this repository is licensed under the GNU General
Public License, version 3 or later, with the Manifold-Woflo Research Components
Exception.

The legal instruments in this `LICENSE.md` and in `LICENSES/**` are not project
source or documentation covered by a project-code license. Each is governed by
the copying permission stated in its own text.

- [GNU GPL version 3](LICENSES/GPL-3.0-or-later.txt)
- [Manifold-Woflo Research Components Exception 1.0](LICENSES/MANIFOLD-WOFLO-EXCEPTION-1.0.md)

Manifold-specific code that calls, displays, tests, or integrates a protected
research component remains GPL-covered unless its own path is listed below.
That includes the app's UI surfaces that render research output and the test
suites that exercise the research components.

## Woflo research components: WLCSL-1.0

These paths are licensed under the
[Woflo Labs Community Source License 1.0](LICENSES/WLCSL-1.0.md):

- `apps/desktop-flutter/lib/backend/logos_*.dart`
- `apps/desktop-flutter/lib/backend/spectral_*.dart`
- `apps/desktop-flutter/lib/backend/engram_*.dart`
- `apps/desktop-flutter/lib/backend/aperture_sweep.dart`
- `apps/desktop-flutter/lib/backend/bond_protocol.dart`
- `apps/desktop-flutter/lib/backend/file_coupling.dart`
- `apps/desktop-flutter/lib/backend/geometric_tokenizer.dart`
- `apps/desktop-flutter/lib/backend/gyat.dart`
- `apps/desktop-flutter/lib/backend/lrg_rings.dart`
- `apps/desktop-flutter/lib/backend/shadow_coupling.dart`
- `apps/desktop-flutter/lib/backend/shadow_coupling_cache.dart`
- `apps/desktop-flutter/lib/backend/trajectory_echoes.dart`
- `apps/desktop-flutter/lib/backend/uase.dart`
- `apps/desktop-flutter/lib/backend/wick.dart`
- `apps/desktop-flutter/assets/engram/alexandria.endb`
- `experiments/**`
- `docs/logos-backend-architecture.md`
- `docs/architecture/coupling-axis-audit.md`
- `docs/architecture/engine-performance-profile.md`
- `docs/architecture/logos-perf-audit.md`
- `docs/architecture/spectral-context-projection.md`
- `docs/architecture/varrho-self-core.md`

A `*` in a path above matches within a single directory; the `**` entry covers
that directory tree. Covered files whose format allows comments also carry a
`LicenseRef-WLCSL-1.0` notice, so the applicable license is usually visible
from the file itself as well as from this list. This list controls.

## Combined Manifold builds

The Manifold-Woflo exception permits the GPL-covered parts of Manifold to be
linked, combined, and distributed with the WLCSL-covered research components.
Each part keeps its own license, and a combined distribution must satisfy the
GPL, the exception, and the applicable terms for the research components.

The exception permits the combination; it does not convert the research
components to GPL or waive their conditions. A GPL-only fork may remove the
protected components and the code paths that require them, but this notice does
not promise that such a configuration already compiles unchanged.

## Contributions

Contributions accepted after this notice follow the
[Woflo Labs Contributor Agreement 1.0](LICENSES/CONTRIBUTOR-AGREEMENT-1.0.md)
and the acceptance process in [CONTRIBUTING.md](CONTRIBUTING.md).

A contribution accepted into a GPL-covered path is promised back publicly under
GPL-3.0-or-later with the Manifold-Woflo exception. A contribution accepted
into one of the research paths above is promised back publicly under WLCSL-1.0.

## Patents, third-party material, and names

Some Woflo research components may implement subject matter described in
pending patent applications. WLCSL-1.0 grants patent rights only for the uses
stated there. "Patent pending" does not mean that a patent has issued or that
any particular claim will be allowed.

Dependencies, referenced projects, vendor material, and files carrying their
own notices are not relicensed here; their own terms continue to apply. Bundled
third-party assets, including the fonts and the quantized GloVe vocabulary
under `apps/desktop-flutter/assets/`, are inventoried in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Neither license grants trademark rights in Woflo Labs, Manifold, Whisper,
Logos, Engram, Kizuna, GYAT, Filament, Orrery, or related names and visual
identities, except the descriptive attribution allowed by the applicable
license.

Woflo Labs is Michael Bickford's publishing and independent research identity,
not a separate incorporated entity as of this notice.
