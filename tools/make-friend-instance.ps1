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

if (-not $OutFile) { $OutFile = Join-Path (Split-Path -Parent $toolsDir) "$Name.zip" }

$stage = Join-Path ([System.IO.Path]::GetTempPath()) "gleamveil-instance-$(Get-Random)"
$mcDir = Join-Path $stage '.minecraft'
New-Item -ItemType Directory -Path $mcDir -Force | Out-Null

Copy-Item $bootstrap (Join-Path $mcDir 'packwiz-installer-bootstrap.jar')

# Prism runs PreLaunchCommand with the working directory set to .minecraft,
# and expands $INST_JAVA to the instance's own Java binary.
$preLaunch = '"$INST_JAVA" -jar packwiz-installer-bootstrap.jar -s client ' + $PackUrl

@"
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
"@ | Set-Content -Path (Join-Path $stage 'instance.cfg') -Encoding UTF8

@"
{
    "components": [
        {
            "cachedName": "Minecraft",
            "important": true,
            "uid": "net.minecraft",
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
"@ | Set-Content -Path (Join-Path $stage 'mmc-pack.json') -Encoding UTF8

if (Test-Path $OutFile) { Remove-Item $OutFile }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $OutFile
Remove-Item $stage -Recurse -Force

Write-Host ""
Write-Host "Built $OutFile" -ForegroundColor Green
Write-Host "Friends: Prism Launcher -> Add Instance -> Import from zip -> pick this file."
Write-Host "Pack URL baked in: $PackUrl"
