package main

/*
#include <unistd.h>
#include <stdio.h>
// A trivial cgo call that compiles against the stock 10.9 SDK headers, to prove
// the toolchain builds + links + runs a cgo program on the box. (The runtime's
// own clock_gettime shim is exercised just by `go` running, and is proven
// defined in-binary by the compat guard.)
static long my_pid(void) { return (long)getpid(); }
*/
import "C"

import "fmt"

func main() {
	fmt.Printf("mavericks-go cgo ok: pid=%d\n", int64(C.my_pid()))
}
