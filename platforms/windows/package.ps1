# Build and package the Windows desktop app (Flutter bundle + chatvv_ffi.dll).
#
# Canonical location. scripts/package-desktop-windows.ps1 is a compatibility shim.
#
# Environment:
#   CHATVV_VULKAN   AUTO (default), ON (CI), OFF
#   VCPKG_ROOT      vcpkg checkout (default: C:\vcpkg)
#
# Requirements: Visual Studio 2022 (C++ workload), vcpkg, Flutter, Rust
# (x86_64-pc-windows-msvc; read-aloud is linked statically into chatvv_ffi.dll),
# and the LunarG Vulkan SDK when CHATVV_VULKAN=ON.
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
$Vcpkg = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { "C:\vcpkg" }
$VulkanMode = if ($env:CHATVV_VULKAN) { $env:CHATVV_VULKAN } else { "AUTO" }

if (!(Test-Path "$Vcpkg\vcpkg.exe")) {
  if (!(Test-Path $Vcpkg)) { git clone --depth 1 https://github.com/microsoft/vcpkg $Vcpkg }
  & "$Vcpkg\bootstrap-vcpkg.bat"
}
& "$Vcpkg\vcpkg.exe" install --classic --triplet x64-windows-static curl sqlite3

cmake -S $Root -B "$Root\build\windows-ffi" -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_TOOLCHAIN_FILE="$Vcpkg\scripts\buildsystems\vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static -DVCPKG_MANIFEST_MODE=OFF `
  -DCHATVV_VULKAN="$VulkanMode"
cmake --build "$Root\build\windows-ffi" --target chatvv_ffi --config Release

Push-Location "$Root\app"
try {
  flutter pub get
  dart run rive_native:setup --verbose -p windows

  # rive_native's setup downloads the prebuilt libs into the pub-cache package
  # (windows/bin/lib/<config>) and copies them into
  # app/build/rive_native/native/build/windows/bin. A cold pub cache can still
  # leave the path read by the plugin CMake
  # (windows/flutter/ephemeral/.plugin_symlinks/rive_native/windows/bin) without
  # lib/release/rive_native.lib (fresh-runner LNK1181). Locate the libs anywhere
  # under the app build dir and copy them into every candidate plugin path,
  # preserving their relative path so the CMake layout stays correct.
  $RiveBuild = "$Root\app\build\rive_native\native\build\windows\bin"
  if (Test-Path $RiveBuild) {
    $RiveFiles = Get-ChildItem -Path $RiveBuild -Recurse -File -ErrorAction SilentlyContinue
    Write-Host "rive_native build dir: $RiveBuild"
    foreach ($f in $RiveFiles) {
      Write-Host "  found: $($f.FullName)"
    }
    $RiveTargets = @()
    $PubCache = if ($env:PUB_CACHE) { $env:PUB_CACHE } else { "$env:LOCALAPPDATA\Pub\Cache" }
    Get-ChildItem -Path (Join-Path $PubCache "hosted\pub.dev") -Directory -Filter "rive_native-*" -ErrorAction SilentlyContinue | ForEach-Object {
      $RiveTargets += (Join-Path $_.FullName "windows\bin")
    }
    $RiveTargets += "$Root\app\windows\flutter\ephemeral\.plugin_symlinks\rive_native\windows\bin"
    foreach ($RivePkgBin in $RiveTargets) {
      if (!(Test-Path (Join-Path $RivePkgBin "lib\release\rive_native.lib"))) {
        Write-Host "repairing rive_native windows libs: $RivePkgBin"
        New-Item -ItemType Directory -Force -Path $RivePkgBin | Out-Null
        foreach ($f in $RiveFiles) {
          $rel = $f.FullName.Substring($RiveBuild.Length).TrimStart('\')
          $dst = Join-Path $RivePkgBin $rel
          New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
          Copy-Item $f.FullName $dst -Force
        }
      }
      Write-Host "rive lib present at $RivePkgBin : $(Test-Path (Join-Path $RivePkgBin "lib\release\rive_native.lib"))"
    }
  }

  $CommitCount = (git -C $Root rev-list --count HEAD).Trim()
  $CommitSha = (git -C $Root rev-parse --short HEAD).Trim()
  $Version = "0.1.$CommitCount"
  # --no-pub: `flutter build` otherwise runs an implicit `pub get` that
  # re-materializes windows/flutter/ephemeral (discarding the rive_native libs
  # repaired above), which made the link fail on cold-cache runners.
  flutter build windows --release --no-pub `
    --build-name=$Version --build-number=$CommitCount `
    --dart-define=APP_VERSION=$Version `
    --dart-define=BUILD_NUMBER=$CommitCount `
    --dart-define=BUILD_COMMIT=$CommitSha
  $Out = "$Root\app\build\windows\x64\runner\Release"
  Copy-Item "$Root\build\windows-ffi\Release\chatvv_ffi.dll" $Out
  New-Item -ItemType Directory -Force -Path "$Root\artifacts" | Out-Null
  Compress-Archive -Path "$Out\*" -DestinationPath "$Root\artifacts\chatvv-windows-x64.zip" -Force
  Write-Host "packaged $Root\artifacts\chatvv-windows-x64.zip"
} finally {
  Pop-Location
}
