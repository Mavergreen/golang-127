package main

/*
#include <stdbool.h>
bool SecTrustEvaluateWithError(void *t, void **e);
*/
import "C"

import (
	"crypto/x509"
	"fmt"
)

func main() {
	_, err := x509.SystemCertPool()
	fmt.Println("cgo-own-polyfill ok", err == nil, bool(C.SecTrustEvaluateWithError(nil, nil)))
}
