#include "procmon.h"
#include <AppKit/AppKit.h>
#include "ProcWatcher.h"

void MonitorProcesses() {
    [[ProcWatcher shared] startWatching];
    [[NSRunLoop currentRunLoop] run];
}
