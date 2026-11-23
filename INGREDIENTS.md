# Build ingredients

Everything baked into the shipped `.pkg`s, and how a change to it reaches a release. An
*ingredient* is an input to the product; the *own upstream* is the thing this repo exists to
port. An own-upstream bump cuts `<upstream>-mavericks.1`; an ingredient bump cuts a
`-mavericks.(N+1)` repackage of the same upstream, via
`.github/workflows/repackage-on-ingredient-bump.yml`.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| Go source (own upstream) | `UPSTREAM_VERSION` | ✅ `golang-version` datasource, **capped to this line** (`<1.28`), patch-automerged | `release.yml` on push to main cuts `-mavericks.1` |
| Recaulk (librecaulk.a, prebuilt) | `components/recaulk/version` | ✅ shipyard preset (github-releases on Mavergreen/recaulk) | watched path → repackage dispatched |
| golang-port (the trust overlay and the build chain) | `components/golang-port/version` | ✅ `renovate.json` customManager (github-releases on Mavergreen/golang-port, tags `v*`) | watched path → repackage dispatched |
| clang22 (compiles and links everything; both pkgs require it) | `components/clang22/version` | ✅ `renovate.json` customManager (github-releases on Mavergreen/clang-22) | watched path → repackage dispatched |
| curl.se CA bundle | `vendor/cacert.pem`, hash-pinned by `CA_SHA256` in `line.env` | ❌ **untrackable — manual refresh** (see below) | both are watched paths → repackage dispatched when the refresh lands |
| Bootstrap Go (builds the toolchain) | `go-version: '1.27.x'` on `actions/setup-go` in `.github/workflows/release.yml` | ✅ github-actions `uses-with`, **capped to this line** (`<1.28`) | `release.yml` is not a watched path, so cut the repackage deliberately |
| MacOSX10.9 SDK, Sparkle framework | `Mavergreen/shipyard@v1` | ✅ github-actions manager tracks the tag | `@v1` is a *moving* tag, so content moves without any path changing (see below) |

Not ingredients: `patches/` (the hook patches) and `line.env`'s other constants are this repo's own recipe — a change there is
a repackage you cut deliberately (`workflow_dispatch` with `local_release=true`), not something
Renovate drives.

## Why the bootstrap Go is capped to this line

(golang-126, 2026-09) Go is self-hosting: the `go-version` handed to `actions/setup-go` is the
compiler that builds the toolchain we ship. That makes it an ingredient, not CI housekeeping, and
it went undeclared here until it proved the point — Renovate opened "update dependency go to
1.27.x" against a repo capped to 1.26.x, and it was mergeable. Automerge is ship-if-green, so
nothing but a passing build stood between us and a 1.26 toolchain built by a 1.27 compiler.

Two things were wrong with that. Changing the compiler changes a shipped artifact's inputs with no
upstream reason — `UPSTREAM_VERSION` is still 1.26.5, so the product did not change, only how it was
made. And no BUILD INPUT may be on 1.27 in a repo that must never build it: a new Go line is a new
repo.

So it is capped `<1.27` like the line itself, and still tracked within it: 1.26.x bootstrap updates
land normally. Raising the cap is the same deliberate act as creating a new line repo.

## Why the CA bundle is untracked

`CA_URL` is a rolling URL (`https://curl.se/ca/cacert.pem`), so there is no version for Renovate to
compare — and scraping curl.se's extract page for the current date would be exactly the fragile
tracker we don't want.

Nothing drifts in the meantime, because the bundle is **vendored**: golang-port's `build/fetch-ca.sh` uses the
committed `vendor/cacert.pem` and verifies it against `CA_SHA256`, and only re-downloads when that
file is absent or `MAVERICKS_CA_REFRESH=1` says to. Builds are reproducible and a rotation upstream
changes nothing here until someone chooses to take it.

So the cost of being untracked is not a broken build — it's that **nobody is told** when Mozilla
publishes new roots. Refresh deliberately:

```sh
# set CA_SHA256 in line.env to the new bundle's sha256 first; this downloads, verifies and rewrites vendor/cacert.pem
MAVERICKS_CA_REFRESH=1 LINE_ROOT="$PWD" sh "$(sh build/port.sh)/build/fetch-ca.sh"
# commit both files
```

That commit touches `line.env` *and* `vendor/cacert.pem`, both of which the repackage
caller watches, so the rebuilt-with-new-roots release cuts itself.

If the silence ever matters more than the simplicity, the clean fix is a dated pin
(`https://curl.se/ca/cacert-YYYY-MM-DD.pem`) plus a Renovate custom datasource over curl.se's
extract page — a real version to bump instead of a bare hash.

## Why `shipyard@v1` is a blind spot

`@v1` is a moving major tag, so shipyard's own commits change what we build with while the pin
string stays `v1`. Renovate can only tell us about `v1 → v2`. That is deliberate (shipyard is
ours, and its changes are gated by its own CI), but it means a shipyard fix does **not**
auto-repackage anything downstream — cut those repackages by hand when they matter.

## The cross toolchain takes its SDK from Longboat

The 10.9 SDK is Apple's, so neither pkg carries it. The cross tree's `SDKs` is a link to
`../sdk109/SDKs`, which `sudo longboat sdk install 10.9` fills. Every darwin/amd64 binary is external-linked against it, so
the cross pkg requires Longboat 20261019.1 or later (the first with `longboat sdk install`) and `sdk109`;
consumers get both from install@v1 with `products: go127-cross@<tag>`. Should `sdk109` go missing later,
`mavericks-cross-clang` stops at its first use and names that command. The build itself reaches the
SDK at sdk109's installed prefix (golang-port's PORT.md, "Fixed C-toolchain paths").

## Conformance deviations

- rosetta:.github/workflows/release.yml: the release job optionally installs Rosetta (`softwareupdate --install-rosetta --agree-to-license || true`) so `tests/rosetta-selftest.sh` can exercise the cross-produced darwin/amd64 toolchain by running it, not just inspecting its files. Both the install and the test invocation are `|| true`: this step never gates the build, it only adds a self-test when Rosetta happens to be available on the runner. Reconsider when this self-test can run on an x86_64 host (the 10.9 box or an Intel runner) instead; at the latest before macOS 28 removes Rosetta.
- sdk-pin:*/src/debug/dwarf/testdata/typedef.macho*: upstream Go's DWARF test fixtures, Mach-O objects the Go team compiled long ago; shipped verbatim as source-tree testdata and never run as a program
- sdk-pin:*/src/runtime/race/*darwin*.syso: upstream Go's prebuilt race-detector runtime objects, shipped verbatim as part of std's source tree and linked only into a user's -race build
- sdk-pin:*/go127-cross/bin/*: Go 1.27 requires macOS 13 and its linker stamps 13.0 (macho.go macVersionFlag{13,0,0}); the cross toolchain's own binaries are Go-linked, not relinked against the pinned SDK.
- sdk-pin:*/go127-cross/pkg/tool/darwin_arm64/*: Go 1.27 requires macOS 13 and its linker stamps 13.0 (macho.go macVersionFlag{13,0,0}); the cross toolchain's own binaries are Go-linked, not relinked against the pinned SDK.
- floor:golang-*-cross-*.pkg: the cross toolchain runs on macOS 13 and later (arm64) and only targets 10.9 -- Go 1.27 requires macOS 13 -- so its archive's install floor is 13.0, not 10.9.5
- product-layout: the two pkgs are staged by golang-port's `build/package.sh`, which calls `stage_product.sh`; this line holds only its inputs and runs the port's build chain (`build/port.sh` resolves the pinned port), so no script here calls it. Exit: shipyard's conventions gate recognises a pinned golang-port (`components/golang-port/version`) as the stager, after which this line goes.
- on-target: no 10.9 acceptance job yet; exit: a release.yml job on Mavergreen/mavericks-vm@v1 that installs this run's pkg in the guest and runs what it ships, which publish needs
