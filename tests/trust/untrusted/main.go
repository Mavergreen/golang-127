package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"fmt"
	"math/big"
	"os"
	"time"
)

func must[T any](v T, err error) T {
	if err != nil {
		fmt.Println("SETUP", err)
		os.Exit(2)
	}
	return v
}

func main() {
	now := time.Now()
	caKey := must(ecdsa.GenerateKey(elliptic.P256(), rand.Reader))
	caTmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "Mavergreen untrusted test CA"},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.Add(24 * time.Hour),
		KeyUsage:              x509.KeyUsageCertSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
	}
	ca := must(x509.ParseCertificate(must(x509.CreateCertificate(rand.Reader, caTmpl, caTmpl, &caKey.PublicKey, caKey))))
	leafKey := must(ecdsa.GenerateKey(elliptic.P256(), rand.Reader))
	leafTmpl := &x509.Certificate{
		SerialNumber: big.NewInt(2),
		Subject:      pkix.Name{CommonName: "untrusted.invalid"},
		DNSNames:     []string{"untrusted.invalid"},
		NotBefore:    now.Add(-time.Hour),
		NotAfter:     now.Add(24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	leaf := must(x509.ParseCertificate(must(x509.CreateCertificate(rand.Reader, leafTmpl, ca, &leafKey.PublicKey, caKey))))
	if _, err := leaf.Verify(x509.VerifyOptions{DNSName: "untrusted.invalid"}); err != nil {
		fmt.Printf("REJECTED %T\n", err)
		return
	}
	fmt.Println("VERIFIED")
}
