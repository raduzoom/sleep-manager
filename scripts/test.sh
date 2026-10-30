#!/bin/zsh
# Runs the unit tests. The Command Line Tools keep the Swift Testing macro plugin in a
# subfolder SwiftPM doesn't search, so point the compiler at it.
set -euo pipefail
cd "${0:A:h}/.."
swift test -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing" "$@"
