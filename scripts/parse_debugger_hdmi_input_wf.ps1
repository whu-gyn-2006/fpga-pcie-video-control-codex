param(
    [string]$Path = "data.wf"
)

$ErrorActionPreference = "Stop"
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
$ficWidth = 7
$rawWidth = $ficWidth + 1
$totalBits = [UInt64]($bytes.Length * 8)
if (($totalBits % [UInt64]$rawWidth) -ne 0) {
    throw "Unexpected waveform size $($bytes.Length); expected packed $rawWidth-bit records."
}
$sampleCount = [int]($totalBits / [UInt64]$rawWidth)

function Get-RawBit([UInt64]$bit) {
    $byteIndex = [int][Math]::Floor([double]$bit / 8.0)
    $bitIndex = [int]($bit % 8)
    return (($bytes[$byteIndex] -shr $bitIndex) -band 1)
}

function Get-Channel([int]$sample, [int]$channel) {
    $start = [UInt64]$sample * [UInt64]$rawWidth
    return Get-RawBit ($start + [UInt64](1 + $channel))
}

function Get-Value([int]$sample, [int]$lsb, [int]$width) {
    [UInt64]$value = 0
    for ($bit = 0; $bit -lt $width; $bit++) {
        $value = $value -bor ([UInt64](Get-Channel $sample ($lsb + $bit)) -shl $bit)
    }
    return $value
}

$names = @('r_hdmi_de_d1 seen','video_crtl DE seen','video_crtl VS seen','frame_done seen','AXIS valid seen','AXIS ready seen','AXIS last seen')
$high = New-Object int[] $ficWidth
$states = @{}
$commands = @{}
$pixValues = New-Object System.Collections.Generic.HashSet[UInt64]
$lastSample = $sampleCount - 1

for ($sample = 0; $sample -lt $sampleCount; $sample++) {
    for ($channel = 0; $channel -lt $ficWidth; $channel++) { $high[$channel] += Get-Channel $sample $channel }
}

$stateNames = @{
    1 = "IDLE"; 2 = "CONECT"; 4 = "INIT"; 8 = "WAIT"
    16 = "STA_RD"; 32 = "SETING"; 64 = "RD_BAK"
}
$stateText = ($states.GetEnumerator() | Sort-Object Name | ForEach-Object {
    $name = if ($stateNames.ContainsKey([int]$_.Name)) { $stateNames[[int]$_.Name] } else { "UNKNOWN" }
    "0x{0:x2}({1})={2}" -f [int]$_.Name, $name, $_.Value
}) -join ", "
$commandText = ($commands.GetEnumerator() | Sort-Object Name | ForEach-Object {
    "{0}={1}" -f [int]$_.Name, $_.Value
}) -join ", "

Write-Host "Decoded $sampleCount samples, FIC=$ficWidth bits, raw=$rawWidth bits"
for ($channel = 0; $channel -lt $ficWidth; $channel++) { Write-Host ("{0}: high={1}/{2}" -f $names[$channel],$high[$channel],$sampleCount) }
if ($high[0] -eq 0) { Write-Host 'RESULT: delayed HDMI DE did not reach video_crtl.' }
elseif ($high[1] -eq 0 -or $high[2] -eq 0) { Write-Host 'RESULT: video_crtl did not produce DE/VS.' }
elseif ($high[3] -eq 0) { Write-Host 'RESULT: video path ran but no complete frame was reported.' }
elseif ($high[4] -eq 0 -or $high[6] -eq 0) { Write-Host 'RESULT: frame completion did not reach AXIS valid/last.' }
else { Write-Host 'RESULT: video_crtl and AXIS produced frame activity.' }
