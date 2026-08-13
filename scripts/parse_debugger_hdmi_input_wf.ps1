param(
    [string]$Path = "data.wf"
)

$ErrorActionPreference = "Stop"
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
$ficWidth = 31
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

$rstHigh = 0
$initHigh = 0
$deSeenHigh = 0
$vsSeenHigh = 0
$states = @{}
$commands = @{}
$pixValues = New-Object System.Collections.Generic.HashSet[UInt64]
$lastSample = $sampleCount - 1

for ($sample = 0; $sample -lt $sampleCount; $sample++) {
    $rstHigh += Get-Channel $sample 0
    $initHigh += Get-Channel $sample 1
    $state = Get-Value $sample 2 7
    $command = Get-Value $sample 9 9
    $null = $pixValues.Add((Get-Value $sample 21 8))
    if (!$states.ContainsKey($state)) { $states[$state] = 0 }
    if (!$commands.ContainsKey($command)) { $commands[$command] = 0 }
    $states[$state]++
    $commands[$command]++
    $deSeenHigh += Get-Channel $sample 29
    $vsSeenHigh += Get-Channel $sample 30
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

$freqBitsLast = Get-Value $lastSample 19 2
$pixFirst = Get-Value 0 21 8
$pixLast = Get-Value $lastSample 21 8

Write-Host "Decoded $sampleCount samples, FIC=$ficWidth bits, raw=$rawWidth bits"
Write-Host ("rstn_out: high={0}/{1}" -f $rstHigh, $sampleCount)
Write-Host ("MS7200 init_over: high={0}/{1}" -f $initHigh, $sampleCount)
Write-Host ("MS7200 states: {0}" -f $stateText)
Write-Host ("MS7200 cmd_index: {0}" -f $commandText)
Write-Host ("MS7200 freq_ensure(last)={0}, freq_rec[17:16](last)=0b{1}" -f `
    (Get-Channel $lastSample 18), [Convert]::ToString([int]$freqBitsLast, 2).PadLeft(2, '0'))
Write-Host ("pixclk counter: first=0x{0:x2}, last=0x{1:x2}, distinct={2}" -f `
    $pixFirst, $pixLast, $pixValues.Count)
Write-Host ("DE seen: high={0}/{1}, VS seen: high={2}/{1}" -f `
    $deSeenHigh, $sampleCount, $vsSeenHigh)

if ($rstHigh -eq 0) {
    Write-Host "RESULT: HDMI receiver reset was never released."
} elseif ($initHigh -eq 0) {
    Write-Host "RESULT: MS7200 initialization did not complete; inspect state/cmd_index and I2C."
} elseif ($pixValues.Count -le 1) {
    Write-Host "RESULT: MS7200 initialized, but no pixel-clock activity reached the FPGA input."
} elseif ($deSeenHigh -eq 0 -or $vsSeenHigh -eq 0) {
    Write-Host "RESULT: Pixel clock is active, but DE/VS did not both appear at the FPGA input."
} else {
    Write-Host "RESULT: MS7200 init and pixel/DE/VS input activity are present; continue after the input boundary."
}
