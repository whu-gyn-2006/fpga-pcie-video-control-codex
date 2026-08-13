param([string]$Path = 'data.wf')
$ErrorActionPreference = 'Stop'
$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
$names = @(
    'start', 'video_de', 'video_vs', 'start_pix_sync', 'line_req_pix',
    'line_req_pcie_d0', 'line_req_pcie_d1', 'line_req_pcie_d2',
    'dma_req', 'dma_cmd_rdy', 'dma_tx_done'
)
$ficWidth = $names.Count
$rawWidth = $ficWidth + 1
$totalBits = [UInt64]($bytes.Length * 8)
if (($totalBits % $rawWidth) -ne 0) { throw "Unexpected waveform size $($bytes.Length) for $rawWidth-bit records." }
$samples = [int]($totalBits / $rawWidth)
function Get-WaveBit([UInt64]$BitOffset) {
    $byteIndex = [int]($BitOffset -shr 3)
    $bitIndex = [int]($BitOffset -band 7)
    return (($bytes[$byteIndex] -shr $bitIndex) -band 1)
}
$high = New-Object int[] $ficWidth
$edges = New-Object int[] $ficWidth
$previous = New-Object int[] $ficWidth
for ($sample = 0; $sample -lt $samples; $sample++) {
    $base = [UInt64]$sample * $rawWidth
    for ($channel = 0; $channel -lt $ficWidth; $channel++) {
        $value = Get-WaveBit -BitOffset ($base + [UInt64](1 + $channel))
        if ($sample -gt 0 -and $value -ne $previous[$channel]) { $edges[$channel]++ }
        $high[$channel] += $value
        $previous[$channel] = $value
    }
}
"Decoded $samples pclk_div2 samples"
for ($channel = 0; $channel -lt $ficWidth; $channel++) {
    '{0,-20} high={1,4} edges={2,4}' -f $names[$channel], $high[$channel], $edges[$channel]
}
if ($high[0] -eq 0) { 'RESULT: legacy start is absent.' }
elseif ($high[3] -eq 0) { 'RESULT: start does not reach the pixel-clock domain.' }
elseif ($high[1] -eq 0 -and $high[2] -eq 0) { 'RESULT: video_crtl has no DE/VS activity.' }
elseif ($high[4] -eq 0) { 'RESULT: video is active but pcie_tx_fun does not form a line request.' }
elseif ($high[7] -eq 0) { 'RESULT: pixel-domain line request does not cross into pclk_div2.' }
elseif ($high[8] -eq 0) { 'RESULT: synchronized line request does not produce a DMA request.' }
elseif ($high[10] -eq 0) { 'RESULT: DMA request is issued but never completes.' }
else { 'RESULT: the complete first-frame path is active.' }
