# procmon

procmon is a small Go program for OSX that watches App launch and terminate
events in AppKit. This project demonstrates the following useful techniques:

- how to call C code from Go with cgo
- how to link Apple frameworks into a  cgo project
- how to call Go code from C with cgo
- how to integrate the callback-based concurrency model of AppKit into Go's CSP-style concurrency model

The Go program directly links against the
[AppKit](https://developer.apple.com/reference/appkit) framework and uses it to
subscribe to the
[NSNotificationCenter](https://developer.apple.com/reference/foundation/nsnotificationcenter)
notifications generated by the OS when the user launches or terminates an App.
The observer itself is written in Objective-C. The Objective-C observer is
accessed by the Go program through a simple C function. The Objective-C
observer, upon seeing notifications, invokes a Go function directly, passing
control back to our Go program.

## installation

Via Go Get: `go get github.com/jordanorelli/procmon`

You can also clone this package and build it with `go build`. The Go toolchain
will invoke cgo transparently on your behalf. There should be no reason to
invoke the cgo toolchain manually; that should only be of interest for
debugging and learning purposes.

## construction

[`procmon.go`](procmon.go) is the single Go file of interest to the
Go toolchain.

### triggering the cgo generation and link step

Accessing cgo requires importing the pseudo-package `C`. It's important to
understand that there is no literal `C` package in the Go standard library.
Every project that uses cgo generates _its own_ `C` package transparently.

When invoking `import "C"`, the comment that _immediately_ precedes the import
directive contains a set of instructions to feed to cgo, as follows:

```go
/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework AppKit
#include "procmon.h"
*/
import "C"
```

Any lines starting with `#cgo` indicate cgo directives. These are passed to the
cgo tool and are used to invoke the necessary compiler and linker. We use these
flags to indicate that we want to invoke the Objective-C compiler and link
agains the AppKit framework.

The other lines in this comment, that is, the lines that do _not_ begin with
`#cgo`, are passed to the C compiler as if they were in a C header file. For our
project, that is just one line: the line that includes `procmon.h`, the header
file for the C code that we want to access.

Down [in the Go program's `main` function](procmon.go#L50), we spawn a goroutine to listen on a
channel for changes:

```go
    go reportChanges()
```

The `reportChanges` function simply reads values off of a channel and prints
them:

```go
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
```

We then invoke the C function `MonitorProcesses`, which we declared in our C
header file. In Go, the invocation looks like this:
```go
    C.MonitorProcesses()
```

And in our header file, the declaration looks like this:
```c
void MonitorProcesses();
```

The cgo toolchain automatically associated `procmon.c` with our header file
`procmon.h` that we imported in our cgo import comment. [The implementation of
the `MonitorProcesses` function appears in
`procmon.c`](procmon.c#L5):

```obj-c
void MonitorProcesses() {
    [[ProcWatcher shared] startWatching];
    [[NSRunLoop currentRunLoop] run];
}
```

This function does two things: it starts by accessing a singleton of our
Objective-C class `ProcWatcher` (that's `[ProcWatcher shared]`, which is defined
[here](ProcWatcher.m#L6)) and
invoking its `startWatching` method. This subscribes our `ProcWatcher` instance
to OS notifications. We'll come back to how the ProcWatcher subscribes to
events in a bit.

#### sidebar: the Run Loop

After signing up for the notifications, we access the current processes'
Run Loop with `[NSRunLoop currentRunLoop]` and call its
[`run`](https://developer.apple.com/reference/foundation/nsrunloop/1412430-run?language=objc)
method to run the Run Loop. There are two reasons why we need to start the
Run Loop. The first has to do with the mechanics of AppKit. NSRunLoop represents
the event loop underpinning our notification center. Without the Run Loop
running, the notification center won't ever pick up any notifications. Apple
has a wealth of documentation with respect to the mechanics of Run Loops. If
you're _extremely curious_ about this part of the project, [this
page](https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html)
has some great literature on how the Run Loop is operating inside of AppKit.

The other reason we invoke the Run Loop in this way is that calling our
Run Loop's run method blocks until the Run Loop itself terminates. Since we're
invoking the C function from within the Go program's `main` function, we're
blocking Go's `main` function, thus preventing `main` from returning. If `main`
returns in the Go program, the Go runtime ends the process, which is _not_ what
we want. So this call gives us two things: it sets up the notification system
infrastructure, and it prevents our program from terminating.

#### back to observing NSNotifications

[The `startWatching`
method](ProcWatcher.m#L6)
accesses the current OSX user's
[`NSWorkspace`](https://developer.apple.com/reference/appkit/nsworkspace). The
`NSWorkspace` handle allows us to hook into
[`NSNotificationCenter`](https://developer.apple.com/reference/foundation/nsnotificationcenter)
to subscribe to notifications in the user's workspace. We specifically
subscribe to the `NSWorkspaceDidLaunchApplicationNotification` and
`NSWorkspaceDidTerminateApplicationNotification` notifications. Here's the
subscription to the `NSWorkspaceDidLaunchApplicationNotification` notification,
which is signaled by the operating system to inform an observer that an
application has been launched by the user:

```obj-c
    void (^handleAppLaunch) (NSNotification*) = ^(NSNotification* note) {
        NSDictionary* info = note.userInfo;
        NSRunningApplication* app = info[NSWorkspaceApplicationKey];
        NSString* bundleId = app.bundleIdentifier;

        AppStarted((GoString){bundleId.UTF8String, bundleId.length});
    };

    id observerLaunch = [notifications
        addObserverForName: NSWorkspaceDidLaunchApplicationNotification
                    object: workspace
                     queue: [NSOperationQueue mainQueue]
                usingBlock: handleAppLaunch];
```

The notable feature here is: we pass a callback to our notification center, and
within that callback, we invoke a curious function: `AppStarted`. That function
isn't defined anywhere in our C or Objective-C code: it's defined [in our
original Go file
`procmon.go`](procmon.go#L28-L31):

```go
//export AppStarted
func AppStarted(name string) {
    appChanges <- appStateChange{stateStarted, name}
}
```

The `//export AppStarted` line before the definition of the Go function informs
cgo that we'd like the function to be exported for use by C with the name
AppStarted. I gave it the same name in C and Go but the names don't have to be
the same; you could `//export SomethingElse` or even `//export something_else`
and invoke it from C as `something_else`.

Because we're exporting a function for use by C, cgo will generate some
bridging code in C that can be imported by our own C code. This allows our own
C code to call back into the Go program and invoke Go functions. cgo will
silently generate this C header file behind the scenes. That C header file,
which is given the totally obvious and well-documented name `_cgo_export.h` is
generated when you run `go build` by cgo, used to help compile our C code, and
then deleted. You won't notice it getting written and deleted because it goes
by so quickly, but it's there, and it's on disk when our C code gets compiled.
In order to access those definitions from our C code, our C code has to import
this fleeting header file. In this project, that inclusion happens in
`ProcWatcher.m`
[here](ProcWatcher.m#L1), which
looks like this:

```c
#include "_cgo_export.h"
```

Any time you access a Go function from C, you almost certainly need to import
the `_cgo_export.h` header file. Importing this header file makes the Go
function accessible to the Objective-C code _as a C function_ which will
automatically cross-call into Go, having the following signature:

```c
void AppStarted(GoString p0);
```

And _that_ is the function that we're invoking in our NSNotification observer
when we call this:

```obj-c
AppStarted((GoString){bundleId.UTF8String, bundleId.length});
```

The `GoString` type is used to convert a null-terminated C string into a Go
string, which appears as a struct at the C level, having the following
definition (and transitive definitions):

```c
typedef struct { const char *p; GoInt n; } GoString;
typedef GoInt64 GoInt;
typedef long long GoInt64;
```

Anyway, calling that C function invokes the corresponding Go function
`AppStarted`, which writes a value onto a channel. That value is read off of
the channel by our `reportChanges` goroutine and used to print out the name of
the App that had been launched or terminated by the user.
