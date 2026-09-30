# Go 1.27 for Mavericks

Go toolchain for Mac OS X 10.9 Mavericks.

## Compiling

### Directly on Mavericks

```sh
sudo installer -pkg golang-<version>-native-mavericks*.pkg -target /
```

In a new Terminal:

```sh
go-127 build -o hello hello.go
./hello
```

### From Apple Silicon

```sh
sudo installer -pkg golang-<version>-cross-mavericks*.pkg -target /
```

In a new Terminal:

```sh
GOARCH=amd64 go-127 build -o hello hello.go
scp hello your-mavericks-system:
```
