[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Fic,
    [Parameter(Mandatory = $true)]
    [string]$Adf
)

$ErrorActionPreference = 'Stop'
foreach ($path in @($Fic, $Adf)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing file: $path"
    }
}

$text = Get-Content -LiteralPath $Fic -Raw
$widthMatch = [regex]::Match($text, 'triggerPortWidth<0>=(\d+)')
if (-not $widthMatch.Success) {
    throw 'FIC has no triggerPortWidth<0>.'
}
$width = [int]$widthMatch.Groups[1].Value
$channelCount = ([regex]::Matches($text, 'triggerChannel<0><\d+>=')).Count
if ($channelCount -ne $width) {
    throw "FIC channel count $channelCount does not match width $width."
}

$designMatch = [regex]::Match($text, 'Project\.device\.designInputFile=(.+)')
if (-not $designMatch.Success) {
    throw 'FIC has no designInputFile.'
}
$ficAdf = $designMatch.Groups[1].Value.Trim().Replace('/', '\')
$expectedAdf = [IO.Path]::GetFullPath($Adf)
if ([IO.Path]::GetFullPath($ficAdf) -ne $expectedAdf) {
    throw "FIC ADF mismatch: $ficAdf`nExpected: $expectedAdf"
}

if ($text -match 'D:/work/demo|D:/work/fpga') {
    throw 'FIC contains a stale D:/work path.'
}

Write-Host "FIC text check passed: width=$width channels=$channelCount"
Write-Host "ADF: $expectedAdf"
