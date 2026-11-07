#!/bin/zsh
# Runs the test suite. With only the Command Line Tools installed (no Xcode), Swift Testing lives
# outside the default search paths, so point the compiler and linker at it.
set -e
cd "$(dirname "$0")/.."
CLT=/Library/Developer/CommandLineTools/Library/Developer
if xcode-select -p | grep -q CommandLineTools; then
  swift test -Xswiftc -F -Xswiftc $CLT/Frameworks -Xlinker -F -Xlinker $CLT/Frameworks \
    -Xlinker -rpath -Xlinker $CLT/Frameworks -Xlinker -rpath -Xlinker $CLT/usr/lib "$@"
else
  swift test "$@"
fi
