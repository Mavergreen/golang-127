# golang

**This README has not been read or edited by a human yet.** Until it has, this project cannot cut
its first release.

A patched Go 1.27.1 toolchain that installs and runs on Mac OS X 10.9 Mavericks (Intel x86_64),
plus a native arm64 cross toolchain that targets 10.9 from a modern Mac (the cross toolchain itself
needs macOS 13 or later to run).

## Install

Download the latest `.pkg` from [Releases](https://github.com/Mavergreen/golang-127/releases/latest)
and open it. The toolchain keeps itself current via a Sparkle updater.

It installs to `/usr/local/mavergreen/go127`. `go-127` is always on your `PATH`; bare `go` belongs
to whichever member of group `go` you've selected (`sudo mavergreen select go go127` to pick this
one).

This is the Go 1.27 line. Its sibling line lives at
[Mavergreen/golang-126](https://github.com/Mavergreen/golang-126).
