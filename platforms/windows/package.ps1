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

  # rive_native's setup is supposed to download the prebuilt libs into the
  # pub-cache package (windows/bin/lib/<config>) and copy them into the app
  # build dir. On cold GitHub runners that download/unzip can end up empty and
  # the plugin link then fails with LNK1181 rive_native.lib. Fetch the artifacts
  # ourselves in that case (explicit URL from the package version.txt) and copy
  # them into every location the plugin/build may read.
  function Copy-RiveTree([string]$Src, [string]$Dst) {
    New-Item -ItemType Directory -Force -Path $Dst | Out-Null
    Get-ChildItem -Path $Src -Recurse -Force | ForEach-Object {
      $rel = $_.FullName.Substring($Src.Length).TrimStart('\')
      $target = Join-Path $Dst $rel
      if ($_.PSIsContainer) {
        New-Item -ItemType Directory -Force -Path $target | Out-Null
      } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item $_.FullName $target -Force
      }
    }
  }

  $PubCache = if ($env:PUB_CACHE) { $env:PUB_CACHE } else { "$env:LOCALAPPDATA\Pub\Cache" }
  $RivePkg = Get-ChildItem -Path (Join-Path $PubCache "hosted\pub.dev") -Directory -Filter "rive_native-*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
  if ($RivePkg -ne $null) {
    $RivePkgBin = Join-Path $RivePkg.FullName "windows\bin"
    $RiveLib = Join-Path $RivePkgBin "lib\release\rive_native.lib"
    Write-Host "rive_native package: $($RivePkg.FullName)"
    Write-Host "rive lib before repair: $(Test-Path $RiveLib)"
    if (!(Test-Path $RiveLib)) {
      $RiveVersion = (Get-Content (Join-Path $RivePkg.FullName "version.txt")).Trim()
      $RiveUrl = "https://rive-flutter-artifacts.rive.app/rive_native_versions/$([Uri]::EscapeDataString($RiveVersion))/rive_native_artifacts_windows.zip"
      Write-Host "downloading rive_native artifacts: $RiveUrl"
      $RiveZip = Join-Path $env:TEMP "rive_native_windows_artifacts.zip"
      Invoke-WebRequest -Uri $RiveUrl -OutFile $RiveZip -UseBasicParsing
      New-Item -ItemType Directory -Force -Path $RivePkgBin | Out-Null
      Expand-Archive -Path $RiveZip -DestinationPath $RivePkgBin -Force
      Remove-Item $RiveZip -Force
      Write-Host "rive lib after download: $(Test-Path $RiveLib)"
    }
    # The Flutter plugin reads the pub-cache package path; also keep the app
    # build dir (used by flutter test) and the ephemeral plugin copy in sync.
    $RiveBuild = "$Root\app\build\rive_native\native\build\windows\bin"
    $RiveEph = "$Root\app\windows\flutter\ephemeral\.plugin_symlinks\rive_native\windows\bin"
    foreach ($Target in @($RiveBuild, $RiveEph)) {
      if (!(Test-Path (Join-Path $Target "lib\release\rive_native.lib"))) {
        Write-Host "repairing rive_native libs: $Target"
        Copy-RiveTree $RivePkgBin $Target
      }
      Write-Host "rive lib present at $Target : $(Test-Path (Join-Path $Target "lib\release\rive_native.lib"))"
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
