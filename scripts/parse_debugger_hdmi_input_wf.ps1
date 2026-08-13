param([string]$Path = "data.wf")
$ErrorActionPreference = "Stop"
$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
$names = @('de_in','r_hdmi_de_d0','r_hdmi_de_d1','video_crtl_de','vs_in','r_hdmi_vs_d0','r_hdmi_vs_d1','video_crtl_vs')
$rawWidth = 9
$bits = [UInt64]($bytes.Length * 8)
if (($bits % $rawWidth) -ne 0) { throw "Unexpected waveform size $($bytes.Length) for 9-bit records." }
$samples = [int]($bits / $rawWidth)
function Bit([UInt64]$n) { return (($bytes[[int]($n / 8)] -shr [int]($n % 8)) -band 1) }
$high = New-Object int[] 8
$edges = New-Object int[] 8
$prev = New-Object int[] 8
for ($s=0;$s -lt $samples;$s++) {
    $base=[UInt64]$s*9
    for($c=0;$c -lt 8;$c++) {
        $v=Bit ($base+[UInt64](1+$c))
        if($s -gt 0 -and $v -ne $prev[$c]){$edges[$c]++}
        $high[$c]+=$v; $prev[$c]=$v
    }
}
"Decoded $samples pixel-clock samples"
for($c=0;$c -lt 8;$c++){"{0,-18} high={1,4} edges={2,4}" -f $names[$c],$high[$c],$edges[$c]}
if($high[0] -eq 0){'RESULT: raw DE absent in this pixel-clock capture.'}
elseif($high[1] -eq 0 -or $high[2] -eq 0){'RESULT: DE is lost in the d0/d1 input register chain.'}
elseif($high[3] -eq 0){'RESULT: DE reaches video_crtl input but not its output.'}
elseif($high[4] -eq 0 -or $high[5] -eq 0 -or $high[6] -eq 0){'RESULT: VS is absent or lost in the input register chain.'}
elseif($high[7] -eq 0){'RESULT: VS reaches video_crtl input but not its output.'}
else{'RESULT: raw, delayed, and video_crtl DE/VS are all active in pixclk_in domain.'}
