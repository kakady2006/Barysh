# Links the Barysh addon folder from this repository into the game's AddOns folder.
# Usage: powershell -ExecutionPolicy Bypass -File tools\install.ps1 -AddOnsDir "<WoW>\_<flavor>_\Interface\AddOns"
param(
    [Parameter(Mandatory = $true)][string]$AddOnsDir
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '..\Barysh' | Resolve-Path
$target = Join-Path $AddOnsDir 'Barysh'

if (-not (Test-Path $AddOnsDir)) {
    throw "AddOns folder not found: $AddOnsDir"
}

if (Test-Path $target) {
    $item = Get-Item $target
    if ($item.LinkType -ne 'Junction') {
        throw "$target already exists and is not a link. Move it away first."
    }
    Write-Host "Link already exists: $target -> $($item.Target)"
} else {
    # A junction needs no administrator rights, unlike a symbolic link.
    New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    Write-Host "Linked $target -> $source"
}

$market = Join-Path $source 'Data\Market.lua'
if (-not (Test-Path $market)) {
    Copy-Item (Join-Path $source 'Data\Market.default.lua') $market
    Write-Host "Created $market from the placeholder"
}
