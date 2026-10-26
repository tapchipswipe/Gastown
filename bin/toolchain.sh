#!/bin/bash
# Prefer the stable SDK when the preview CLT lacks the SwiftUI macro plugin.
if [[ -n "${NEWTON_SDK:-}" ]]; then
    newton_sdk="$NEWTON_SDK"
elif [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    newton_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
else
    newton_sdk="$(xcrun --sdk macosx --show-sdk-path)"
fi
