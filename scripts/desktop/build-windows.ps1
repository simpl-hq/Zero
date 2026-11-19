<#
.SYNOPSIS
  Build and package Zero on Windows from Cmder or PowerShell.

.DESCRIPTION
  Wraps GHC 9.6.3, Cabal, MSYS2 UCRT64 (bundled inside C:\ghcup\msys64),
  OpenSSL 3.0.15, and Gradle/JDK 17 so all Windows build targets can be run
  directly from Cmder or Windows PowerShell without manually launching a
  separate MSYS2 shell.

.PARAMETER Target
  cli     - Build OpenSSL 3.0.15 and all Haskell binaries/tests (zero-runtime.exe, etc.).
  test    - Run the Hspec test suite (cabal test --test-show-details=direct).
  lib     - Build libzero.dll and fetch VLC desktop runtime dependencies.
  desktop - Build lib (if missing) and launch the Compose Desktop app locally.
  msi     - Build lib (if missing) and package the Windows .msi installer.
  all     - Run cli, lib, and msi sequentially.

.EXAMPLE
  .\scripts\desktop\build-windows.ps1 -Target cli
  .\scripts\desktop\build-windows.ps1 -Target test
  .\scripts\desktop\build-windows.ps1 -Target desktop
  .\scripts\desktop\build-windows.ps1 -Target msi
#>
[CmdletBinding()]
param(
  [ValidateSet('cli', 'test', 'lib', 'desktop', 'msi', 'all')]
  [string]$Target = 'cli',
  [switch]$SkipCabalUpdate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function ConvertTo-MsysPath {
  param([Parameter(Mandatory)][string]$WindowsPath)
  $full = [System.IO.Path]::GetFullPath($WindowsPath)
  if ($full -match '^([A-Za-z]):(.*)$') {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = $Matches[2] -replace '\\', '/'
    return "/$drive$rest"
  }
  return ($full -replace '\\', '/')
}

function Find-Jdk17Home {
  $candidates = @()
  if ($env:JAVA_HOME) {
    $candidates += $env:JAVA_HOME
  }
  foreach ($base in @(
    'C:\Program Files\Eclipse Adoptium',
    (Join-Path $env:LOCALAPPDATA 'Programs\Eclipse Adoptium'),
    'C:\Program Files\Microsoft',
    'C:\Program Files\Java',
    'C:\Program Files\Amazon Corretto',
    'C:\Program Files\BellSoft'
  )) {
    if (Test-Path $base) {
      Get-ChildItem $base -Directory -Filter '*17*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { $candidates += $_.FullName }
    }
  }
  foreach ($dir in ($candidates | Select-Object -Unique)) {
    $javaExe = Join-Path $dir 'bin\java.exe'
    if (Test-Path $javaExe) {
      $oldEap = $ErrorActionPreference
      $ErrorActionPreference = 'Continue'
      try {
        $verOut = (& $javaExe -version 2>&1) -join "`n"
      }
      finally {
        $ErrorActionPreference = $oldEap
      }
      if ($verOut -match '"17\.') {
        return $dir
      }
    }
  }
  return $null
}

function Find-WixBinDir {
  $candle = Get-Command candle.exe -ErrorAction SilentlyContinue
  $light = Get-Command light.exe -ErrorAction SilentlyContinue
  if ($candle -and $light) {
    return (Split-Path $candle.Source -Parent)
  }
  foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
    if (-not $pf -or -not (Test-Path $pf)) { continue }
    $dirs = Get-ChildItem $pf -Directory -Filter '*WiX*' -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending
    foreach ($d in $dirs) {
      foreach ($bin in @((Join-Path $d.FullName 'bin'), $d.FullName)) {
        if ((Test-Path (Join-Path $bin 'candle.exe')) -and (Test-Path (Join-Path $bin 'light.exe'))) {
          return $bin
        }
      }
    }
  }
  return $null
}

function Resolve-Toolchains {
  $ghcupBin = 'C:\ghcup\bin'
  $ghcExe = Join-Path $ghcupBin 'ghc.exe'
  $cabalExe = Join-Path $ghcupBin 'cabal.exe'
  if (-not (Test-Path $ghcExe) -or -not (Test-Path $cabalExe)) {
    throw "GHC or Cabal not found in $ghcupBin. Install with: ghcup install ghc 9.6.3 --set; ghcup install cabal 3.10.2.0 --set"
  }

  $msysRoot = 'C:\ghcup\msys64'
  $msysBash = Join-Path $msysRoot 'usr\bin\bash.exe'
  $ucrtBin = Join-Path $msysRoot 'ucrt64\bin'
  if (-not (Test-Path $msysBash)) {
    throw "MSYS2 bash not found at $msysBash."
  }
  if (-not (Test-Path (Join-Path $ucrtBin 'gcc.exe')) -or -not (Test-Path (Join-Path $msysRoot 'usr\bin\make.exe'))) {
    throw "MSYS2 UCRT64 build tools missing. Install with: & C:\ghcup\msys64\usr\bin\pacman.exe -Sy --noconfirm --needed make git perl zip unzip mingw-w64-ucrt-x86_64-toolchain mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja"
  }

  $needsJava = $Target -in @('desktop', 'msi', 'all')
  $needsCmake = $Target -in @('desktop', 'msi', 'all')
  $needsWix = $Target -in @('msi', 'all')

  if ($needsCmake -and -not (Test-Path (Join-Path $ucrtBin 'cmake.exe'))) {
    throw "CMake missing in $ucrtBin. Install with: & C:\ghcup\msys64\usr\bin\pacman.exe -Sy --noconfirm --needed mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja"
  }

  $jdkHome = Find-Jdk17Home
  if ($needsJava -and -not $jdkHome) {
    throw "JDK 17 not found. Install with: winget install --id EclipseAdoptium.Temurin.17.JDK -e"
  }

  $wixBin = Find-WixBinDir

  return [pscustomobject]@{
    GhcupBin   = $ghcupBin
    MsysBash   = $msysBash
    MsysUsrBin = (Join-Path $msysRoot 'usr\bin')
    UcrtBin    = $ucrtBin
    JdkHome    = $jdkHome
    WixBin     = $wixBin
  }
}

function Invoke-Msys2Bash {
  param(
    [Parameter(Mandatory)][pscustomobject]$Tools,
    [Parameter(Mandatory)][string]$ScriptBody
  )

  $oldMsystem = $env:MSYSTEM
  $oldChere = $env:CHERE_INVOKING
  $tmpWin = [System.IO.Path]::GetTempFileName()
  try {
    $env:MSYSTEM = 'UCRT64'
    $env:CHERE_INVOKING = '1'
    $repoMsys = ConvertTo-MsysPath $RepoRoot
    $fullScript = @(
      'set -euo pipefail'
      'export PATH="/c/ghcup/bin:$PATH"'
      "cd `"$repoMsys`""
      $ScriptBody
    ) -join "`n"
    $fullScript = ($fullScript -replace "`r`n", "`n") + "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmpWin, $fullScript, $utf8NoBom)
    $tmpMsys = ConvertTo-MsysPath $tmpWin
    & $Tools.MsysBash -l $tmpMsys
    if ($LASTEXITCODE -ne 0) {
      throw "MSYS2 bash command failed with exit code $LASTEXITCODE"
    }
  }
  finally {
    if (Test-Path $tmpWin) { Remove-Item $tmpWin -Force -ErrorAction SilentlyContinue }
    $env:MSYSTEM = $oldMsystem
    $env:CHERE_INVOKING = $oldChere
  }
}

function Ensure-NanoHttpdSubmodule {
  $probe = Join-Path $RepoRoot 'apps\multiplatform\external\nanohttpd\upstream\core\src\main\java\org\nanohttpd'
  if (-not (Test-Path $probe)) {
    Write-Host '[zero] Initializing nanohttpd git submodule...'
    Push-Location $RepoRoot
    try {
      git submodule update --init --recursive
      if ($LASTEXITCODE -ne 0) {
        throw "git submodule update failed with exit code $LASTEXITCODE"
      }
    }
    finally {
      Pop-Location
    }
  }
}

function Invoke-BuildCli {
  param([Parameter(Mandatory)][pscustomobject]$Tools)

  $cabalUpdateCmd = if ($SkipCabalUpdate) { ':' } else { 'cabal update' }
  $script = @"
scripts/desktop/prepare-openssl-windows.sh
openssl_win=`$(cygpath -w "`$PWD/dist-newstyle/openssl-3.0.15")
rm -f cabal.project.local
cat > cabal.project.local << EOF
ignore-project: False
package zeroq
    extra-include-dirs: `${openssl_win}\include
    extra-lib-dirs: `${openssl_win}
package direct-sqlcipher
    flags: +openssl
    extra-include-dirs: `${openssl_win}\include
    extra-lib-dirs: `${openssl_win}
EOF
rm -rf dist-newstyle/src/direct-sq* dist-newstyle/src/zeroq*
$cabalUpdateCmd
cabal build -j --enable-tests
bin_path=`$(cabal list-bin exe:zero-runtime | tail -n 1)
echo "[zero] Built CLI binary: `$bin_path"
"@
  Write-Host '[zero] Building OpenSSL 3.0.15 + Haskell CLI/tests...'
  Invoke-Msys2Bash -Tools $Tools -ScriptBody $script
}

function Invoke-TestSuite {
  param([Parameter(Mandatory)][pscustomobject]$Tools)

  Invoke-BuildCli -Tools $Tools
  Write-Host '[zero] Running Haskell Hspec test suite (zero-runtime-test)...'
  Invoke-Msys2Bash -Tools $Tools -ScriptBody @'
export PATH="$PWD/dist-newstyle/openssl-3.0.15:$PATH"
cabal test zero-runtime-test --test-show-details=direct
'@
}

function Invoke-BuildLib {
  param([Parameter(Mandatory)][pscustomobject]$Tools)

  Write-Host '[zero] Building libzero.dll + fetching VLC desktop libs...'
  Invoke-Msys2Bash -Tools $Tools -ScriptBody './scripts/desktop/build-lib-windows.sh'
}

function Invoke-GradleTask {
  param(
    [Parameter(Mandatory)][pscustomobject]$Tools,
    [Parameter(Mandatory)][string]$GradleTask
  )

  Ensure-NanoHttpdSubmodule
  $libZero = Join-Path $RepoRoot 'apps\multiplatform\common\src\commonMain\cpp\desktop\libs\windows-x86_64\libzero.dll'
  if (-not (Test-Path $libZero)) {
    Invoke-BuildLib -Tools $Tools
  }

  $oldPath = $env:PATH
  $oldJavaHome = $env:JAVA_HOME
  $oldAndroidHome = $env:ANDROID_HOME
  $oldAndroidSdkRoot = $env:ANDROID_SDK_ROOT
  $oldCc = $env:CC
  $oldCxx = $env:CXX
  $multiplatformDir = Join-Path $RepoRoot 'apps\multiplatform'
  Push-Location $multiplatformDir
  try {
    $env:JAVA_HOME = $Tools.JdkHome
    if (-not $env:ANDROID_HOME) {
      $defaultSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
      if (Test-Path $defaultSdk) {
        $env:ANDROID_HOME = $defaultSdk
        $env:ANDROID_SDK_ROOT = $defaultSdk
      }
    }
    $extraPath = @("$($Tools.JdkHome)\bin", $Tools.UcrtBin)
    if ($Tools.WixBin) {
      $extraPath += $Tools.WixBin
    }
    $env:PATH = ($extraPath -join ';') + ';' + $oldPath + ';' + $Tools.MsysUsrBin
    $env:CC = (Join-Path $Tools.UcrtBin 'gcc.exe')
    $env:CXX = (Join-Path $Tools.UcrtBin 'g++.exe')

    Write-Host "[zero] Running .\gradlew.bat '-Pzero.assets.dir=../../assets' $GradleTask ..."
    & .\gradlew.bat '-Pzero.assets.dir=../../assets' $GradleTask
    if ($LASTEXITCODE -ne 0) {
      throw "Gradle task '$GradleTask' failed with exit code $LASTEXITCODE"
    }

    if ($GradleTask -eq 'packageMsi') {
      $msi = Get-ChildItem (Join-Path $multiplatformDir 'release\main\msi') -Filter '*.msi' -ErrorAction SilentlyContinue |
        Select-Object -First 1
      $setupExe = Get-ChildItem (Join-Path $multiplatformDir 'release\main\exe') -Filter '*.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
      if ($msi) {
        Write-Host "[zero] Built Windows MSI installer: $($msi.FullName)"
      }
      if ($setupExe) {
        Write-Host "[zero] Built Windows Setup GUI:    $($setupExe.FullName)"
      }
    }
  }
  finally {
    Pop-Location
    $env:PATH = $oldPath
    $env:JAVA_HOME = $oldJavaHome
    $env:ANDROID_HOME = $oldAndroidHome
    $env:ANDROID_SDK_ROOT = $oldAndroidSdkRoot
    $env:CC = $oldCc
    $env:CXX = $oldCxx
  }
}

$tools = Resolve-Toolchains
switch ($Target) {
  'cli'     { Invoke-BuildCli -Tools $tools }
  'test'    { Invoke-TestSuite -Tools $tools }
  'lib'     { Invoke-BuildLib -Tools $tools }
  'desktop' { Invoke-GradleTask -Tools $tools -GradleTask 'run' }
  'msi'     { Invoke-GradleTask -Tools $tools -GradleTask 'packageMsi' }
  'all' {
    Invoke-BuildCli -Tools $tools
    Invoke-BuildLib -Tools $tools
    Invoke-GradleTask -Tools $tools -GradleTask 'packageMsi'
  }
}
