#!/bin/sh
# Assembles the MCPB bundle folder (and packs it if the `mcpb` CLI is installed).
# Publishing it (GitHub Release, MCP Registry) is a human step; see docs/05-distribution.md §7.2.
# Claude Desktop will likely need the binary signed with Developer ID and notarized (GATE).
set -e
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/Core/Version.swift)
swift build -c release --arch arm64 --arch x86_64
OUT=dist/mcpb
rm -rf "$OUT" && mkdir -p "$OUT/server"
cp packaging/mcpb/manifest.json "$OUT/"
cp .build/apple/Products/Release/intents-mcp "$OUT/server/"
grep -q "\"version\": \"$VERSION\"" "$OUT/manifest.json" || { echo "manifest version != $VERSION" >&2; exit 1; }
if command -v mcpb >/dev/null; then
  mcpb validate "$OUT/manifest.json"
  mcpb pack "$OUT" "dist/intents-mcp-$VERSION.mcpb"
  shasum -a 256 "dist/intents-mcp-$VERSION.mcpb"
else
  echo "bundle folder ready at $OUT (install the mcpb CLI to validate and pack: npm i -g @anthropic-ai/mcpb)"
fi
