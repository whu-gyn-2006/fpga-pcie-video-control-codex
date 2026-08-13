param([string]$Path = "data.wf")
$ErrorActionPreference = "Stop"
$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
$names = @('start','dma_tx_done','frame_done','wr_index[0]','wr_index[1]','line_req_d0','line_req_d1','line_req_d2')
$rawWidth = 9
$totalBits = [UInt64]($bytes.Length * 8)
if (($totalBits % $rawWidth) -ne 0) { throw "Unexpected waveform size $($bytes.Length) for 9-bit records." }
$samples = [int]($totalBits / $rawWidth)
function Get-WaveBit([UInt64]$BitOffset) {
    $byteIndex = [int]($BitOffset -shr 3)
    $bitIndex = [int]($BitOffset -band 7)
    return (($bytes[$byteIndex] -shr $bitIndex) -band 1)
}
$high = New-Object int[] 8
$edges = New-Object int[] 8
$previous = New-Object int[] 8
for ($sample = 0; $sample -lt $samples; $sample++) {
    $base = [UInt64]$sample * $rawWidth
    for ($channel = 0; $channel -lt 8; $channel++) {
        $value = Get-WaveBit -BitOffset ($base + [UInt64](1 + $channel))
        if ($sample -gt 0 -and $value -ne $previous[$channel]) { $edges[$channel]++ }
        $high[$channel] += $value
        $previous[$channel] = $value
    }
}
"Decoded $samples pclk_div2 samples"
for ($channel = 0; $channel -lt 8; $channel++) {
    "{0,-14} high={1,4} edges={2,4}" -f $names[$channel], $high[$channel], $edges[$channel]
}
$index = $previous[3] -bor ($previous[4] -shl 1)
"last write index=$index"
if ($high[0] -eq 0) { 'RESULT: legacy start did not assert.' }
elseif ($high[5] -eq 0 -and $high[6] -eq 0 -and $high[7] -eq 0) { 'RESULT: no synchronized line request reached pclk_div2.' }
elseif ($high[1] -eq 0) { 'RESULT: line requests arrived but DMA never completed a transaction.' }
elseif ($high[2] -eq 0) { 'RESULT: DMA transactions completed but no full frame completed.' }
else { 'RESULT: start, DMA completion, and frame completion are active.' }
