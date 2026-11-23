# PORT.md — what this port carries, and why

Go upstream does not support Mac OS X 10.9. This port carries changes to make it build and run
there. **This file is the authority for why each one exists.** Design specs are history; if a spec
and this file disagree, this file wins, and the change to it goes in the same commit as the code.

Before changing or dropping any carried change during a port to a new Go minor: read its entry.
"Upstream changed this area" is a reason to re-read, never a reason to drop.

## Trust invariants (crypto/x509 on darwin)

These hold on every line. Tests named `TestKeychainUnion*` pin them; `tests/trust/unit-trust.sh`
requires those tests to run and pass. These change only through a trust-policy brainstorm, never
inside a port.

1. **The system roots are the keychain union:** anchors from all three trust domains (user, admin,
   system; Keychain Access semantics, Go 1.16/1.17's code) ∪ certificates from **every existing
   bundle file**, minus every keychain-distrusted certificate. Every bundle contributes — this is
   not a search order. *Why:* one Go verifier over a union of anchors, with distrust as a veto, is
   the model the pkgsrc umbrella chose over Apple's 2013 engine (spec 2026-09-13 §3.2).
   *Reconsider:* removing stale roots (10.9 still trusts roots Mozilla has removed) is a separate
   trust-policy brainstorm, deliberately deferred (specs 2026-09-13 §6, 2026-09-16). Never a side
   effect of a port. Go's verifier does no AIA fetching: a server that omits its intermediate
   certificates fails verification, as with Go on Linux. `GODEBUG=x509usefallbackroots=0` selects
   Apple's verifier, which fetches them. This predates go127 (go126 behaves the same).
2. **A keychain Deny always vetoes** — any built chain containing a distrusted certificate is
   rejected, including a distrusted intermediate the server supplies (patch 0010).
3. **`SSL_CERT_FILE` / `SSL_CERT_DIR` shape the union, never replace it.** `SSL_CERT_FILE` replaces
   the default bundle-file list; `SSL_CERT_DIR` (colon-separated) adds each directory's files; the
   keychain stays in and the veto still applies. *Why:* a user's Never Trust must not silently stop
   applying because a Python/conda environment or a shell rc set `SSL_CERT_FILE` (spec 2026-07-19).
   **Upstream Go 1.27 differs:** it makes these variables exclusive on darwin (on-disk roots only).
   We keep our semantics and say so in release notes. Upstream's `SystemCertPool` doc comment
   (cert_pool.go), which says SSL_CERT_* disables the platform verifier unless
   `x509sslcertoverrideplatform=0`, does not describe darwin in this toolchain.
4. **`GODEBUG=x509sslcertoverrideplatform` has no effect on darwin.** Upstream's `=0` means
   "pre-1.27 behaviour"; ours is invariant 3. It matters: the setting is registered
   `Changed: 27, Old: "0"`, so every program whose go.mod says `go 1.26` or lower gets `=0` by
   default.
5. **`GODEBUG=x509usefallbackroots=0` selects Apple's verifier** (the `systemPool` marker), on every
   macOS version; `=1` with `SetFallbackRoots` uses the program's fallback pool, as upstream does —
   but the keychain-distrust veto still applies, because `initSystemRoots` builds the union first
   (as in go126) before ever swapping in the fallback pool; a program's own `SetFallbackRoots` never
   panics and never displaces the union unless `=1`.
6. **An empty union is an error**, so `Verify` with nil Roots falls back to Apple's verifier and
   `SystemCertPool` reports it.
7. **Default bundle files:** `/usr/local/mavergreen/ca-certs/etc/openssl/certs/ca-certificates.crt`
   (the family's line-independent bundle — a contract the ca-certs product must honour), this line's
   own `@SSLDIR@/certs/ca-certificates.crt`, then `/usr/local/etc/openssl/cert.pem`,
   `/etc/openssl/certs/ca-certificates.crt`, `/etc/ssl/certs/ca-certificates.crt`, `/etc/ssl/cert.pem`.
   Every default path is a trust input: `/usr/local/mavergreen` (and so the ca-certs tree) must be
   root-owned, as must `/usr/local/etc/openssl`. *Reconsider* when the ca-certs product ships: the
   lines may then stop carrying their own bundle copy.

## Hook ↔ overlay interface

Overlay = files added whole (line-independent): crypto/x509's `root_keychainunion*.go` files and
their testdata. **The overlay comes from golang-port** (pinned in `components/golang-port/version`;
its `PORT.md` is the authority for each overlay file, and its build chain applies the overlay after
this line's hook patches). Hooks = edits to upstream files (per-minor; Go churns them), carried here
in `patches/`. A renamed function breaks the hook at compile time, which goes red on the line.

| Hook patch (upstream file) | Uses from the overlay |
|---|---|
| 0010 `verify.go` | `keychainUnionDistrusted`, `keychainUnionFilterDistrusted` |
| 0013 `root_darwin.go` (`systemVerify`) | `keychainUnionLegacySecTrust`, `keychainUnionLegacyEvaluate` |
| 0016 `root.go` (`loadSystemRoots`) | `keychainUnionPlatformRoots` (darwin: `root_keychainunion_darwin.go`; `!darwin`: `root_keychainunion_other.go`) |
| 0018 `root_test.go`, `verify_test.go`, `hybrid_pool_test.go` | — (points readers at `TestKeychainUnion*`) |

| Overlay file (golang-port) | Uses from hooks |
|---|---|
| `root_keychainunion_darwin.go` | 0005/0006's `internal/macos` SecTrustSettings wrappers |

### Upstream internals the overlay relies on

These are what break the overlay across Go minors — none of them are part of the hook/overlay
interface above, but the overlay reaches into upstream's own unexported state to do its job
(golang-port's `PORT.md` keeps the same list):

- `root_keychainunion_darwin.go` uses `x509usefallbackroots` and `CertPool.systemPool`.
- The darwin tests (`root_keychainunion_darwin_test.go`) use `once`, `systemRootsMu`, `systemRoots`,
  `systemRootsErr`, `fallbacksSet` and `useFallbackRoots`.
- 0016 relies on `loadSystemRoots` living in root.go.

## Carried changes

### 0001-make-bash-bootstrap-ldflags.patch
Hook. Injects the Recaulk link flags into cmd/dist's bootstrap build, from
`GO_BOOTSTRAP_LDFLAGS`; inert when unset. *Why:* the bootstrap toolchain must link Recaulk.
*Reconsider:* if the build stops building a bootstrap that runs on 10.9.

### 0002-cmd-dist-buildtool-bootstrap-ldflags.patch
Hook. The same flags for the bootstrap-tools build; inert when unset. *Why/Reconsider:* as 0001.

### 0003-runtime-osinit-hack-version-guard.patch
Hook. Runs the osinit_hack fork+exec-hang workaround only on macOS ≥ 10.12, where
`notify_is_valid_token` exists. *Why:* on 10.9–10.11 the symbol is absent and binding it kills the
binary. *Reconsider:* never while 10.9 is a target.

### 0004-runtime-cgo-no-unknown-pragmas.patch
Hook. Appends `-Wno-unknown-pragmas` to runtime/cgo's flags. *Why:* 10.9's system clang (6.0) warns
on newer pragmas and runtime/cgo builds with `-Werror`, so on-box cgo builds fail. Diagnostic-only.
*Reconsider:* if runtime/cgo drops `-Werror` or its pragmas.

### 0005-macos-sectrustsettings-wrappers.patch
Hook. Restores the SecTrustSettings wrappers upstream removed in 1.26 (Go 1.24/1.18 code), plus the
older-macOS SecTrust calls and `SecTrustGetCssmResultCode`. *Why:* the union reads trust settings the
way Go 1.16/1.17 did (invariant 1); Apple's verifier below 10.15 needs the older calls.
*Reconsider:* never while invariant 1 holds.

### 0006-macos-sectrustsettings-trampolines.patch
Hook. The assembly trampolines for 0005's wrappers. *Why/Reconsider:* as 0005.

### 0010-verify-distrust-veto.patch
Hook. Drops any built chain containing a keychain-distrusted certificate. *Why:* invariant 2 —
anchor exclusion alone cannot reject a distrusted intermediate that also chains to a trusted root.
*Reconsider:* never while invariant 2 holds.

### 0011-cmd-dist-extlink-darwin-amd64.patch
Hook. Lets `GO_EXTLINK_ENABLED=darwin/amd64` be baked in at make.bash time. *Why/Reconsider:* 0012.

### 0012-cmd-link-extlink-darwin-amd64.patch
Hook. `GO_EXTLINK_ENABLED=darwin/amd64`: external-link every darwin/amd64 binary, keep the automatic
choice elsewhere. *Why:* Go internal-links cgo-free binaries, which never run the CC wrapper, so on
10.9 they lack the legacy shim, carry a modern minimum-OS stamp (12.0 in 1.26, 13.0 in 1.27) and die
with `_clock_gettime` unresolved. golang-port's on-target suite (`tests/on-target/run.sh`, its
pure-Go link check) is the gate. *Reconsider:* never while 10.9 is a target.

### 0013-root-darwin-legacy-sectrust.patch
Hook. Makes upstream's `systemVerify` work on 10.9: the SSL policy is passed as a single
`SecPolicyRef` (10.9's SecTrustEvaluate faults on a policies CFArray built by
`CFArrayCreateMutable`), and below 10.15 evaluation and chain extraction use `SecTrustEvaluate` /
`SecTrustGetCertificateAtIndex`. *Why:* invariant 5 — Apple's verifier must work on every macOS.
*Reconsider:* never while invariant 5 holds.

### 0016-root-loadsystemroots-keychainunion-hook.patch
Hook. One statement at the top of `root.go`'s `loadSystemRoots` hands darwin to
`keychainUnionPlatformRoots`. *Why:* Go 1.27 moved darwin's `loadSystemRoots` there from
`root_darwin.go`. Keep it one statement so it survives future moves. *Reconsider:* only if upstream
moves `loadSystemRoots` again.

### 0018-root-test-darwin-keychainunion.patch
Hook (tests). Upstream tests that assert upstream's darwin semantics skip on darwin: `TestEnvVars`
and `TestLoadSystemCertsLoadColonSeparatedDirs` (env-exclusive roots, which we deliberately lack —
invariant 3), and `TestIssue51759` (verify_test.go) and `TestHybridPool` (hybrid_pool_test.go), which
assume Apple's verifier is the default (Apple's error strings; AIA-fetched intermediates —
invariants 1, 5). `TestSSLCertEnvOverride` keeps running and asserts invariant 4 on darwin.
`tests/trust/unit-trust.sh` requires all four skips. *Reconsider:* when upstream's tests stop
asserting upstream's darwin semantics.

### 0019-cmd-link-macos-default-10.9.patch
Hook. A darwin/amd64 link defaults to minimum OS 10.9 instead of Go's 13.0; `-ldflags=-macos=X` still
overrides, and other targets (the cross toolchain's own darwin_arm64 tools) keep 13.0. *Why:* the external
linker is lld (clang22), which warns on every link when Go's go.o claims 13.0 while the target minimum is
10.9; Apple's old ld64 was silent. The binary's floor was already 10.9. golang-port's on-target suite fails
on that warning. *Reconsider:* when Go's own default drops to 10.9 or below (never), or 10.9 stops being a target.

## Not carried here

- The CA bundle itself (`vendor/cacert.pem`, curl.se's Mozilla export) is an ingredient, not a
  change — see INGREDIENTS.md.
- The 10.9 back-fill archive is an ingredient (`Mavergreen/recaulk`, pinned in `components/recaulk/version`).
- The trust overlay and the build chain are golang-port's (`Mavergreen/golang-port`, pinned in
  `components/golang-port/version`); its `PORT.md` explains each overlay file and each build rule.

## Last verified

- 2026-09-25: go1.27.1 on ultimate-hat (10.9.5) -- smoke, pure-go-link, acceptance-onbox (incl. SSL_CERT_FILE); Keychain "Never Trust" on ISRG Root X1 rejected valid-isrgrootx1.letsencrypt.org with and without SSL_CERT_FILE, and restoring Always Trust verified it; cross toolchain minos 13.0
