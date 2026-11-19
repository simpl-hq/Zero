[CmdletBinding()]
param(
  [string]$MsiPath = '',
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$MultiplatformDir = Join-Path $RepoRoot 'apps\multiplatform'
$DistResDir = Join-Path $MultiplatformDir 'desktop\src\jvmMain\resources\distribute'
$CsPath = Join-Path $DistResDir 'windows\ZeroSetup.cs'
$WordmarkPath = Join-Path $DistResDir 'windows\ZeroWordmark.png'
$IconPath = Join-Path $DistResDir 'zero.ico'

$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) {
  throw "C# compiler not found at $csc"
}

function Find-SignTool {
  $st = Get-Command signtool.exe -ErrorAction SilentlyContinue
  if ($st) { return $st.Source }
  foreach ($kits in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if (-not $kits) { continue }
    $bin = Join-Path $kits 'Windows Kits\10\bin'
    if (Test-Path $bin) {
      $found = Get-ChildItem $bin -Recurse -Filter 'signtool.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*\x64\*' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
      if ($found) { return $found.FullName }
    }
  }
  return $null
}

function Invoke-AuthenticodeSign {
  param([string]$FilePath, [string]$PfxPath, [string]$PfxPassword, [string]$SignTool)
  Write-Host "[zero] Signing $(Split-Path $FilePath -Leaf) with Authenticode..."
  & $SignTool sign /f $PfxPath /p $PfxPassword /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $FilePath
  if ($LASTEXITCODE -ne 0) {
    throw "signtool.exe failed for $FilePath with exit code $LASTEXITCODE"
  }
}

if (-not $MsiPath) {
  $found = Get-ChildItem (Join-Path $MultiplatformDir 'release\main\msi') -Filter '*.msi' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { $MsiPath = $found.FullName }
}

if (-not $OutputPath) {
  $exeDir = Join-Path $MultiplatformDir 'release\main\exe'
  New-Item -ItemType Directory -Force -Path $exeDir | Out-Null
  $verLine = Select-String -Path (Join-Path $MultiplatformDir 'gradle.properties') -Pattern '^desktop\.version_name=(.+)$' | Select-Object -First 1
  $ver = if ($verLine) { $verLine.Matches[0].Groups[1].Value.Trim() } else { '1.0.0' }
  $OutputPath = Join-Path $exeDir "Zero-$ver-setup.exe"
} else {
  $outParent = Split-Path $OutputPath -Parent
  if ($outParent) { New-Item -ItemType Directory -Force -Path $outParent | Out-Null }
}

$tempPfx = $null
$manifestCs = $null
try {
  $certB64 = $env:WINDOWS_CERT_BASE64
  $certPwd = $env:WINDOWS_CERT_PASSWORD
  $signTool = $null
  if ($certB64 -and $certPwd) {
    $signTool = Find-SignTool
    if ($signTool) {
      $tempPfx = Join-Path $env:TEMP ("zero-sign-" + [Guid]::NewGuid().ToString("N") + ".pfx")
      [IO.File]::WriteAllBytes($tempPfx, [Convert]::FromBase64String($certB64.Trim()))
    } else {
      Write-Warning "WINDOWS_CERT_BASE64 is set but signtool.exe was not found on this host."
    }
  }

  $wpfDir = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\WPF'
  $args = @(
    '/nologo',
    '/optimize+',
    '/platform:x64',
    '/target:winexe',
    "/win32icon:$IconPath",
    "/out:$OutputPath",
    "/r:$wpfDir\PresentationFramework.dll",
    "/r:$wpfDir\PresentationCore.dll",
    "/r:$wpfDir\WindowsBase.dll",
    '/r:System.Xaml.dll',
    '/r:System.Windows.Forms.dll',
    '/r:System.Drawing.dll',
    "/resource:$WordmarkPath,ZeroWordmark.png"
  )

  if ($MsiPath -and (Test-Path $MsiPath)) {
    if ($tempPfx -and $signTool) {
      Invoke-AuthenticodeSign -FilePath $MsiPath -PfxPath $tempPfx -PfxPassword $certPwd -SignTool $signTool
    }
    $msiHash = (Get-FileHash -Path $MsiPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifestCs = Join-Path $env:TEMP ("SetupManifest-" + [Guid]::NewGuid().ToString("N") + ".g.cs")
    @"
namespace ZeroSetup
{
    internal static partial class SetupManifest
    {
        static partial void ResolveExpectedMsiSha256(ref string value)
        {
            value = "$msiHash";
        }
    }
}
"@ | Set-Content -Path $manifestCs -Encoding UTF8
    $args += "/resource:$MsiPath,Zero.msi"
    $args += $manifestCs
    Write-Host "[zero] Embedding MSI payload ($msiHash): $MsiPath"
  } else {
    Write-Host "[zero] Building standalone ZeroSetup launcher (no embedded MSI found yet)"
  }

  $args += $CsPath
  & $csc @args
  if ($LASTEXITCODE -ne 0) {
    throw "csc.exe failed with exit code $LASTEXITCODE"
  }

  if ($tempPfx -and $signTool -and (Test-Path $OutputPath)) {
    Invoke-AuthenticodeSign -FilePath $OutputPath -PfxPath $tempPfx -PfxPassword $certPwd -SignTool $signTool
  }

  Write-Host "[zero] Built Windows Setup executable: $OutputPath"
}
finally {
  if ($tempPfx -and (Test-Path $tempPfx)) { Remove-Item $tempPfx -Force -ErrorAction SilentlyContinue }
  if ($manifestCs -and (Test-Path $manifestCs)) { Remove-Item $manifestCs -Force -ErrorAction SilentlyContinue }
}
