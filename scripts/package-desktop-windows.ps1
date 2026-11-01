$ErrorActionPreference = "Stop"
$Root = (Resolve-Path "$PSScriptRoot\..").Path
$Vcpkg = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { "C:\vcpkg" }

if (!(Test-Path "$Vcpkg\vcpkg.exe")) {
  if (!(Test-Path $Vcpkg)) { git clone --depth 1 https://github.com/microsoft/vcpkg $Vcpkg }
  & "$Vcpkg\bootstrap-vcpkg.bat"
}
& "$Vcpkg\vcpkg.exe" install --classic --triplet x64-windows-static curl sqlite3

cmake -S $Root -B "$Root\build\windows-ffi" -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_TOOLCHAIN_FILE="$Vcpkg\scripts\buildsystems\vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static -DVCPKG_MANIFEST_MODE=OFF
cmake --build "$Root\build\windows-ffi" --target chatvv_ffi --config Release

Push-Location "$Root\app"
try {
  flutter pub get
  dart run rive_native:setup --verbose -p windows
  flutter build windows --release
  $Out = "$Root\app\build\windows\x64\runner\Release"
  Copy-Item "$Root\build\windows-ffi\Release\chatvv_ffi.dll" $Out
  New-Item -ItemType Directory -Force -Path "$Root\artifacts" | Out-Null
  Compress-Archive -Path "$Out\*" -DestinationPath "$Root\artifacts\chatvv-windows-x64.zip" -Force
  Write-Host "packaged $Root\artifacts\chatvv-windows-x64.zip"
} finally {
  Pop-Location
}
