package main

import (
	"fmt"
	"runtime"
)

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework AppKit
#include "procmon.h"
*/
import "C"

//export TheGoFunc
func TheGoFunc(name string) {
	fmt.Printf("hi from c: %s\n", name)
}

func main() {
	C.TheCFunc()
	runtime.Goexit()
}
