#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -f "$check_dir/MemoryChecks" "$check_dir/MonitorLifecycleChecks"; rmdir "$check_dir"' EXIT
swiftc -parse-as-library Sources/SysMonBar/AppMemorySnapshot.swift \
    Sources/SysMonBar/ProcessTermination.swift Tests/MemoryChecks.swift \
    -o "$check_dir/MemoryChecks"
"$check_dir/MemoryChecks"
swiftc -parse-as-library Sources/SysMonBar/AppMemorySnapshot.swift \
    Sources/SysMonBar/ProcessTermination.swift Sources/SysMonBar/SystemMonitor.swift \
    Sources/SysMonBar/ProcessPanelVisibility.swift Tests/MonitorLifecycleChecks.swift \
    -o "$check_dir/MonitorLifecycleChecks"
"$check_dir/MonitorLifecycleChecks"
