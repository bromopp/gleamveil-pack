<#
.SYNOPSIS
  Builds the Prism Launcher instance zip that friends import once.

.DESCRIPTION
  The zip contains no mods. It contains a pre-launch command that runs
  packwiz-installer against the published pack.toml, so every time a friend
  presses Play their mods are synced to whatever is currently in the pack.
  They import this file once and never touch it again.

.EXAMPLE
  .\make-friend-instance.ps1 -PackUrl https://bruno.github.io/gleamveil-pack/pack.toml
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PackUrl,

    [string] $Name = 'Gleamveil',
    [string] $MinecraftVersion = '1.21.7',
    [string] $FabricVersion = '0.16.14',
    [int]    $MaxMemoryMB = 6144,
    [string] $OutFile
)

$ErrorActionPreference = 'Stop'

if (-not $PackUrl.EndsWith('pack.toml')) {
    throw "PackUrl should point at the pack.toml itself, e.g. https://user.github.io/gleamveil-pack/pack.toml"
}

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$bootstrap = Join-Path $toolsDir 'packwiz-installer-bootstrap.jar'
if (-not (Test-Path $bootstrap)) {
    Write-Host "Fetching packwiz-installer-bootstrap.jar..."
    Invoke-WebRequest -Uri 'https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/packwiz-installer-bootstrap.jar' -OutFile $bootstrap
}

# Optional: pre-adds the server to the multiplayer list so friends don't have to
# type the address. Regenerate with tools/gen-servers-dat.mjs if it changes.
$serversDat = Join-Path $toolsDir 'servers.dat'

if (-not $OutFile) { $OutFile = Join-Path (Split-Path -Parent $toolsDir) "$Name.zip" }

# Prism reads instance.cfg with QSettings and mmc-pack.json as plain JSON;
# neither tolerates a byte-order mark, and Set-Content -Encoding UTF8 emits one
# on Windows PowerShell. Write the bytes ourselves instead.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-PlainText([string] $Text) {
    # Extra parens: inside an argument list PowerShell would otherwise read the
    # -replace operands as separate arguments to GetBytes.
    $utf8NoBom.GetBytes(($Text -replace "`r`n", "`n"))
}

# Prism runs PreLaunchCommand with the working directory set to .minecraft,
# and expands $INST_JAVA to the instance's own Java binary.
$preLaunchRaw = '"$INST_JAVA" -jar packwiz-installer-bootstrap.jar -s client ' + $PackUrl

# instance.cfg is read by Qt's QSettings in INI mode. A value that BEGINS with a
# double quote is parsed as a quoted token, and the whitespace immediately after
# the closing quote is swallowed -- which silently turned
#   "$INST_JAVA" -jar ...
# into
#   C:/.../javaw.exe-jar ...
# and the process failed to start with no useful error.
#
# Escape the inner quotes and do NOT wrap the value. This is byte-for-byte what
# Prism itself writes when the same command is entered through its Custom
# Commands UI, verified against a real instance.
$preLaunch = $preLaunchRaw -replace '"', '\"'

$instanceCfg = @"
[General]
ConfigVersion=1.2
InstanceType=OneSix
name=$Name
iconKey=default
notes=Mods sync automatically from $PackUrl every time you press Play. Do not add or remove mods by hand - they will be reverted on the next launch. Ask Bruno to add anything you want in the pack.
OverrideCommands=true
PreLaunchCommand=$preLaunch
PostExitCommand=
WrapperCommand=
OverrideMemory=true
MinMemAlloc=512
MaxMemAlloc=$MaxMemoryMB
"@

$mmcPack = @"
{
    "components": [
        {
            "cachedName": "Minecraft",
            "important": true,
            "uid": "net.minecraft",
            "version": "$MinecraftVersion"
        },
        {
            "cachedName": "Intermediary Mappings",
            "cachedRequires": [
                {
                    "equals": "$MinecraftVersion",
                    "uid": "net.minecraft"
                }
            ],
            "cachedVolatile": true,
            "dependencyOnly": true,
            "uid": "net.fabricmc.intermediary",
            "version": "$MinecraftVersion"
        },
        {
            "cachedName": "Fabric Loader",
            "cachedRequires": [
                {
                    "uid": "net.fabricmc.intermediary"
                }
            ],
            "uid": "net.fabricmc.fabric-loader",
            "version": "$FabricVersion"
        }
    ],
    "formatVersion": 1
}
"@

# Build the zip by hand. Compress-Archive writes backslash separators, which
# violate the zip spec and are not reliably read back as directories.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (Test-Path $OutFile) { Remove-Item $OutFile }
$zipStream = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::CreateNew)
try {
    $zip = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        function Add-Bytes([string] $EntryName, [byte[]] $Bytes) {
            $entry = $zip.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $s = $entry.Open()
            try { $s.Write($Bytes, 0, $Bytes.Length) } finally { $s.Dispose() }
        }
        Add-Bytes 'instance.cfg'   (Write-PlainText $instanceCfg)
        Add-Bytes 'mmc-pack.json'  (Write-PlainText $mmcPack)
        Add-Bytes '.minecraft/packwiz-installer-bootstrap.jar' ([System.IO.File]::ReadAllBytes($bootstrap))
        if (Test-Path $serversDat) {
            Add-Bytes '.minecraft/servers.dat' ([System.IO.File]::ReadAllBytes($serversDat))
            Write-Host "Included servers.dat (server pre-added to the multiplayer list)."
        } else {
            Write-Warning "tools/servers.dat missing - friends will have to add the server manually."
        }
    } finally { $zip.Dispose() }
} finally { $zipStream.Dispose() }

Write-Host ""
Write-Host "Built $OutFile" -ForegroundColor Green
Write-Host "Friends: Prism Launcher -> Add Instance -> Import from zip -> pick this file."
Write-Host "Pack URL baked in: $PackUrl"
