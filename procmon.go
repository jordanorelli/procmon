package main

import (
	"fmt"
)

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework AppKit
#include "procmon.h"
*/
import "C"

var appChanges = make(chan appStateChange, 1)

type stateChange uint

const (
	stateStarted stateChange = iota
	stateEnded
)

type appStateChange struct {
	stateChange
	appname string
}

//export AppStarted
func AppStarted(name string) {
	appChanges <- appStateChange{stateStarted, name}
}

//export AppEnded
func AppEnded(name string) {
	appChanges <- appStateChange{stateEnded, name}
}

func reportChanges() {
	for change := range appChanges {
		switch change.stateChange {
		case stateStarted:
			fmt.Printf("started: %s\n", change.appname)
		case stateEnded:
			fmt.Printf("terminated: %s\n", change.appname)
		}
	}
}

func main() {
	go reportChanges()
	C.MonitorProcesses()
}
