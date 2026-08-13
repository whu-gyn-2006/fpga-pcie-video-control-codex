param(
    [string]$Path = "data.wf"
)

$ErrorActionPreference = "Stop"
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
$names = @(
    "de_in", "vs_in", "r_hdmi_de_d1", "r_hdmi_vs_d1",
    "w_video_crtl_de", "w_video_crtl_vs", "w_start_flag", "r_vs_rst",
    "frame_done", "r_wr_index_d0[0]", "r_wr_index_d0[1]",
    "axis_master_tvalid_mem", "axis_master_tready_mem", "axis_master_tlast_mem"
)
$ficWidth = $names.Count
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

$high = New-Object int[] $ficWidth
$transitions = New-Object int[] $ficWidth
$first = New-Object int[] $ficWidth
$last = New-Object int[] $ficWidth
$previous = New-Object int[] $ficWidth

for ($sample = 0; $sample -lt $sampleCount; $sample++) {
    $start = [UInt64]$sample * [UInt64]$rawWidth
    for ($channel = 0; $channel -lt $ficWidth; $channel++) {
        $value = Get-RawBit ($start + [UInt64](1 + $channel))
        if ($sample -eq 0) {
            $first[$channel] = $value
            $previous[$channel] = $value
        }
        elseif ($value -ne $previous[$channel]) {
            $transitions[$channel]++
        }
        if ($value -ne 0) {
            $high[$channel]++
        }
        $last[$channel] = $value
        $previous[$channel] = $value
    }
}

Write-Host "Decoded $sampleCount samples, FIC=$ficWidth bits, raw=$rawWidth bits"
for ($channel = 0; $channel -lt $ficWidth; $channel++) {
    "{0,-28} high={1,4} transitions={2,4} first={3} last={4}" -f `
        $names[$channel], $high[$channel], $transitions[$channel], `
        $first[$channel], $last[$channel]
}
