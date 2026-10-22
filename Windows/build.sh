#!/bin/bash
# Builds Isola for Windows from Linux or macOS (needs the .NET 8 SDK), the same as build.ps1 on Windows:
# build/<runtime>/Isola.exe and build/Isola-Windows-<arch>.zip.
#   RUNTIME=win-arm64     (default win-x64)
#   VERSION=1.2.0
#   FRAMEWORK_DEPENDENT=1 much smaller; needs the .NET 8 Desktop Runtime to run
set -euo pipefail
cd "$(dirname "$0")"

RUNTIME="${RUNTIME:-win-x64}"
OUT="build/$RUNTIME"
rm -rf "$OUT"

ARGS=(publish Isola/Isola.csproj -c Release -r "$RUNTIME" -p:PublishSingleFile=true
      -p:IncludeNativeLibrariesForSelfExtract=true -o "$OUT")
if [ "${FRAMEWORK_DEPENDENT:-0}" = "1" ]; then
    ARGS+=(--self-contained false)
else
    ARGS+=(--self-contained true -p:EnableCompressionInSingleFile=true)
fi
[ -n "${VERSION:-}" ] && ARGS+=("-p:Version=$VERSION")

dotnet "${ARGS[@]}"

ZIP="build/Isola-Windows-${RUNTIME#win-}.zip"
rm -f "$ZIP"
(cd "$OUT" && python3 -c 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],"w",zipfile.ZIP_DEFLATED); z.write("Isola.exe"); z.close()' "../Isola-Windows-${RUNTIME#win-}.zip")

echo "Built $OUT/Isola.exe"
echo "Zipped $ZIP"
