# mavericks-golang

Cross-builds a **patched Go 1.27.1 toolchain that installs and runs on Mac OS X 10.9
(Mavericks)** — with out-of-the-box cgo, keychain∪bundle verified TLS, and a Sparkle
auto-updater — entirely on modern hardware. No 10.9 build runner anywhere.

**Status:** The Go 1.27 line, from its sibling `golang-126`, with trust semantics kept
unchanged (hook patches 0005, 0006, 0010, 0013, 0016 and 0018, tracked in `PORT.md`, plus golang-port's
overlay). Built and proven end to
end on real 10.9.5 hardware (`ultimate-hat`) on 2026-09-26, installed side by side with
golang-126: separate trees, updaters and feeds, the selection untouched, the trust
acceptance and the pure-Go link gate all passing, and a clean uninstall. The first release,
`1.27.1-mavericks.1`, is auto-cut by the first push to `main`. Ships as
`golang-<gover>-native-mavericks.<rev>.pkg` and `golang-<gover>-cross-mavericks.<rev>.pkg`,
which install `/usr/local/mavergreen/go127` and `/usr/local/mavergreen/go127-cross`.

## Build / release

- **The build chain is golang-port's** (`Mavergreen/golang-port`, pinned in
  `components/golang-port/version`). This repo holds only the line's inputs: `UPSTREAM_VERSION`,
  `components/{recaulk,clang22,golang-port}/version`, `line.env` (`CROSS_MIN_OS`, `CA_SHA256`), the hook
  `patches/`, `vendor/cacert.pem` and the release notes (the updater's icon and public key, and the pkgs'
  Welcome text, are golang-port's). `build/port.sh` resolves the port:
  `GOLANG_PORT_DIR` on a dev box (announced `UNPINNED`; refused when `MAVERGREEN_RELEASE=yes`), else the
  pinned release tarball verified against its `SHA256SUMS`. Every step is
  `LINE_ROOT=$PWD sh "$PORT_DIR/build/<step>.sh"`; the port's `PORT.md` "Build chain" is the authority for
  the build rules.
- `sh build/build.sh [native] [cross] [linux-cross] [updaters] [packages]` — the whole local build, in order,
  through the port (default: native and cross, plus linux-cross on Linux). Rosetta-free, the same bytes on
  Linux and on the 10.9 box.
- `GO_LINE=<line> sh tests/on-target/run.sh` (from the port) — the on-target suite, in the 10.9 guest against
  the installed pkg.
- `sh tests/trust/smoke-trust.sh` — TLS-trust acceptance (pinned LE endpoints).
- `.github/workflows/release.yml` — CI build → EdDSA-sign → appcast → Release. Three triggers: push
  to `main` (auto-cuts `<upstream>-mavericks.1` if unreleased), a `*-mavericks.*` tag, or
  `workflow_dispatch local_release=true`. Jobs:
  - `build` (`ubuntu-latest`): install@v1 `products:` installs clang22 and Recaulk at their pins
    (`components/*/version`); `MAVERGREEN_RELEASE=yes` makes `build/port.sh` refuse `GOLANG_PORT_DIR`. It runs
    the repo tests, the port's `cross-vet.sh`, `build-native`, `build-cross` and `build-linux-cross`, the compat
    guard (clang22's `llvm-*` as `LIPO`/`OTOOL`/`NM`), both updaters and both pkgs. The archive smoke extracts
    `go127-cross-<version>-linux-x86_64.tar.gz` at `/usr/local/mavergreen/go127-cross` and runs
    `tests/cross-smoke.sh`. It also asserts that `release-assets.sh` selects the archive exactly once, so
    publish's `SHA256SUMS` lists it once. Then sign, appcast and conformance.
  - `on-target` (`ubuntu-latest`, `Mavergreen/mavericks-vm@v1`, PRs too): on a fresh 10.9 guest the native
    pkg must first refuse without clang22, naming it. Then Longboat's sdk109, clang22 and the pkg go in,
    and the port's `tests/on-target/run.sh` runs.
  - `modern-smoke` (`macos-26`, PRs too): installs clang22-cross by install@v1 `products:`, then the cross
    pkg. `go` must run natively on arm64, and `tests/cross-smoke.sh` must pass.
  - `publish` needs `build`, `scan`, `on-target` and `modern-smoke`.
- **This repo ships ONE Go minor line (1.27) from the repo root.** `UPSTREAM_VERSION` and `patches/`
  live at the top level, not under a per-line directory; everything else derives from the line number
  (the products `go127` and `go127-cross` in `/usr/local/mavergreen/`, group `go`,
  `dev.mavergreen.golang.go127`, the product title, and, through shipyard's registry, each updater's
  bundle id, LaunchAgent label and feed `<short>.xml` at `/releases/latest/download/`; there is no
  separate feed release). The line number is itself **derived** from `UPSTREAM_VERSION`
  (`build/version.sh line`; 1.27.1 → 127), never configured separately.
  - **A new Go minor line is a NEW REPO**, forked from this one (`Mavergreen/golang-126` is this
    line's own sibling, forked the same way) — not a second directory here. It inherits this repo's
    `patches/` as its starting point. `docs/` is gitignored here (tracked out-of-band, not present in
    a clone). This repo's Renovate cap (`allowedVersions` on `go-127`, capped just below the next Go
    minor) is what keeps this repo on 1.27.x so it can never drift onto the next line by itself. A new
    line gets noticed the ordinary way: a consumer's routine Renovate bump needing the next Go minor
    fails its build.
  - The gates are what keep a line safe to ship, not fuzzy patch application: the hook patches and
    golang-port's overlay are the keychain-union trust model in `src/crypto/x509`, exactly where Go churns between
    minors. A fuzzy apply (`patch -p0 -F 3`) can succeed and be wrong — that is what `tests/trust/`,
    `tests/port-md-test.sh` and the compat guard are for. **Never relax those to make a build green.**
    `PORT.md` is the authority for why each carried patch exists; a spec disagreeing with it loses.
- Upstream Go version lives in `UPSTREAM_VERSION` (bare `x.y.z`, Renovate-managed) at the repo root.
  `build/version.sh <auto|local>` derives the full `<upstream>-mavericks.N` + a `RELEASE=yes/no`
  decision from existing `*-mavericks.*` tags: `auto` is `N=1`/`RELEASE=yes` for a new upstream (no
  tag yet), else current `N`/`RELEASE=no`; `local` (via `workflow_dispatch local_release`) is always
  `N=maxN+1`/`RELEASE=yes`. `VERSION` (the full string) is workflow-written and **gitignored** —
  never committed.
- Renovate auto-bumps `UPSTREAM_VERSION` (capped to this repo's line) and automerges the PR **once the
  build is green** — patch, minor and major alike, per the family's ship-if-green policy. This repo
  needs no extra `packageRules` beyond the cap: a Go minor bump past the cap never opens a PR at all,
  and within the cap a bad bump just fails the build. The bootstrap Go (`actions/setup-go`) is capped
  the same way (`1.27.x`, capped just below the next Go minor): it is self-hosting and so an
  ingredient, not CI trivia — a golang-126 incident showed a mergeable bump to the next minor's
  bootstrap compiler with nothing but a green build standing in the way. `ignoreTests: false` comes
  from the **shared preset** — don't restate it here, or this repo silently stops tracking the preset.
- A push to `main` whose upstream has no release yet auto-cuts `<upstream>-mavericks.1` via
  `gh release create` in `release.yml` (no PAT — `gh` mints the tag itself). Don't also push a
  manual tag for that release; that re-triggers CI and rebuilds/republishes the same version.

## Non-obvious invariants (details in `memory/`)

- **Repo is on NFS — build on local disk** (`WORK` defaults under `$MAVERICKS_BUILD_ROOT`, `${TMPDIR:-/tmp}/mm-build`). [[mavericks-golang-nfs-build-location]]
- **Every darwin/amd64 link goes through the CC wrapper, pure Go included.** The toolchains are built
  with `GO_EXTLINK_ENABLED=darwin/amd64` baked in (patches 0011/0012): Go internal-links cgo-free
  binaries otherwise, and those die on 10.9 (`_clock_gettime`). Other GOOS targets keep the automatic
  choice. golang-port's on-target suite (`tests/on-target/run.sh`) is the gate.
- **The amd64 toolchain is cross-linked `-linkmode=external`** so the toolchain's own binaries (go/gofmt/tools)
  route through the min-10.9 CC wrapper — Go 1.27 internal-links pure-Go darwin binaries to a 13.0
  floor otherwise (golang-126's Go internal-linked to a 12.0 floor), which the CC wrapper avoids for
  darwin/amd64. `link-recipe.sh` (the old `-extldflags`/`GO_EXTLINK_ENABLED` plumbing) is gone; the CC
  wrappers inject the shim directly. [[mavericks-golang-downstream-linking]]
- **The cross toolchain needs macOS 13+.** `CROSS_MIN_OS` in `line.env` sets the cross
  archive's install floor and the appcast `--min-os`; its own binaries carry Go's own 13.0 stamp
  (Go 1.27's linker defaults `LC_BUILD_VERSION` to macOS 13.0), declared as `sdk-pin`/`floor`
  deviations in `INGREDIENTS.md`. The native toolchain's own floor is unchanged: every darwin/amd64
  link still goes through the min-10.9 CC wrapper, so native output stays 10.9.
- **The trust model:** crypto/x509's system roots on darwin are the keychain union — all three trust
  domains read with Go 1.17's precedence- and policy-aware code, ∪ every existing CA bundle, minus
  distrust — served through a one-line hook at the top of the shared `loadSystemRoots` (hook patches
  here, `PORT.md` the authority for each one, enforced by `tests/port-md-test.sh`; the overlay is
  golang-port's, its `PORT.md` the authority for each overlay file).
  This is kept **unchanged from golang-126 on purpose**, and differs from upstream Go 1.27:
  `SSL_CERT_FILE`/`SSL_CERT_DIR` shape the union's bundle files rather than replacing it, and
  `GODEBUG=x509sslcertoverrideplatform` has no effect on darwin here. `GODEBUG=x509usefallbackroots=0`
  selects Apple's verifier, which works on 10.9: its crash was Go passing a NULL-callback CFArray of
  policies. Reading the USER domain doesn't prompt in any context tested (a locked login keychain is
  untested; the prompt guards writes). Acceptance: `tests/trust/acceptance-onbox.sh` + the
  semi-manual steps in `smoke-trust.sh`.
- **Sparkle updater + EdDSA keys** (private key = `SPARKLE_PRIVATE_KEY` secret). [[mavericks-golang-sparkle-updater]]
- **Renovate's Go patch auto-release trusts go.dev's feed-verified sha256** (golang-port's
  `build/fetch-go.sh` and `build/go-src-sha256.sh`), not a pinned checksum, and requires no PAT/App token — deliberately,
  so don't add one.
- **clang22 compiles and links everything, on every host** (`/usr/local/mavergreen/clang22`, pinned in
  `components/clang22/version`); no Apple `/usr/bin/clang` or Command Line Tools anywhere, and both pkgs
  require clang22 (`go127-cross` requires clang22-cross). Reuse `../mavergreen-shipyard`; don't duplicate.

## Design docs

`docs/superpowers/specs/2026-09-25-*.md` (spec) and `docs/superpowers/plans/2026-09-25-*.md`
(implementation plan) — `docs/` is gitignored here (tracked out-of-band, not present in a clone).
