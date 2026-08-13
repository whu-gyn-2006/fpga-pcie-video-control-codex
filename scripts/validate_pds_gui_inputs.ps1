param(
    [string]$ProjectDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$projectDir = (Resolve-Path -LiteralPath $ProjectDir).Path
$pdsFiles = @(Get-ChildItem -LiteralPath $projectDir -Filter '*.pds')
if ($pdsFiles.Count -ne 1) {
    throw "Expected exactly one PDS file in $projectDir; found $($pdsFiles.Count)."
}

$pdsPath = $pdsFiles[0].FullName
$pdsText = Get-Content -LiteralPath $pdsPath -Raw
$listed = @([regex]::Matches($pdsText, '\(_file\s+"([^"]+)"') | ForEach-Object {
    $_.Groups[1].Value -replace '/', '\'
})
$listedVerilog = @($listed | Where-Object { $_ -match '\.v$' })
$listedFic = @($listed | Where-Object { $_ -match '\.fic$' })
$requiredInputs = @($listed | Where-Object { $_ -match '\.(?:v|sv|vh|fdc|fic)$' })
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Get-ProjectRelativePath([string]$BasePath, [string]$FullPath) {
    $baseUri = [Uri]((Join-Path ([IO.Path]::GetFullPath($BasePath)) '.'))
    $fileUri = [Uri]([IO.Path]::GetFullPath($FullPath))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fileUri).ToString()) -replace '/', '\'
}

foreach ($relativePath in $requiredInputs) {
    $fullPath = Join-Path $projectDir $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $errors.Add("PDS-listed file is missing: $relativePath")
    }
}

$listedFull = @{}
foreach ($relativePath in $listedVerilog) {
    $fullPath = [IO.Path]::GetFullPath((Join-Path $projectDir $relativePath))
    $listedFull[$fullPath.ToLowerInvariant()] = $relativePath
}

$diskDefinitions = @{}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $projectDir 'src') -Recurse -Filter '*.v') {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($match in [regex]::Matches($text, '(?m)^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)')) {
        $name = $match.Groups[1].Value
        if ($diskDefinitions.ContainsKey($name)) {
            $warnings.Add("Duplicate module definition on disk: $name")
        } else {
            $diskDefinitions[$name] = $file.FullName
        }
    }
}

$instantiated = [System.Collections.Generic.HashSet[string]]::new()
foreach ($relativePath in $listedVerilog) {
    $fullPath = Join-Path $projectDir $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) { continue }
    $text = Get-Content -LiteralPath $fullPath -Raw
    foreach ($name in $diskDefinitions.Keys) {
        if ([regex]::IsMatch($text, "(?m)^\s*$([regex]::Escape($name))\s*(?:#\s*\([^;]*?\)\s*)?[A-Za-z_][A-Za-z0-9_$]*\s*\(", 'Singleline')) {
            [void]$instantiated.Add($name)
        }
    }
}

foreach ($name in $instantiated) {
    $definitionPath = [IO.Path]::GetFullPath($diskDefinitions[$name]).ToLowerInvariant()
    if (-not $listedFull.ContainsKey($definitionPath)) {
        $relative = Get-ProjectRelativePath $projectDir $diskDefinitions[$name]
        $errors.Add("Instantiated module '$name' is not in the PDS GUI source list: $relative")
    }
}

foreach ($file in Get-ChildItem -LiteralPath (Join-Path $projectDir 'src') -Recurse -Filter '*.v') {
    $key = $file.FullName.ToLowerInvariant()
    if (-not $listedFull.ContainsKey($key)) {
        $moduleNames = @([regex]::Matches((Get-Content -LiteralPath $file.FullName -Raw), '(?m)^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)') | ForEach-Object { $_.Groups[1].Value })
        $used = @($moduleNames | Where-Object { $instantiated.Contains($_) })
        if ($used.Count -eq 0) {
            $relative = Get-ProjectRelativePath $projectDir $file.FullName
            Write-Host "INFO: disk Verilog not listed and not instantiated: $relative"
        }
    }
}

if ($listedFic.Count -gt 1) {
    $errors.Add("More than one FIC is registered in the PDS GUI: $($listedFic -join ', ')")
}
foreach ($relativePath in $listedFic) {
    $ficPath = Join-Path $projectDir $relativePath
    if (-not (Test-Path -LiteralPath $ficPath)) { continue }
    $ficText = Get-Content -LiteralPath $ficPath -Raw
    $widthMatch = [regex]::Match($ficText, 'triggerPortWidth<0>=(\d+)')
    $channels = @([regex]::Matches($ficText, 'triggerChannel<0><(\d+)>='))
    if (-not $widthMatch.Success) {
        $errors.Add("FIC has no triggerPortWidth<0>: $relativePath")
    } elseif ([int]$widthMatch.Groups[1].Value -ne $channels.Count) {
        $errors.Add("FIC width/channel mismatch in ${relativePath}: width=$($widthMatch.Groups[1].Value), channels=$($channels.Count)")
    }
    if ($ficText -notmatch '(?m)^Project\.device\.designInputFile=.+hdmi_loop_syn\.adf\s*$') {
        $errors.Add("FIC designInputFile does not target hdmi_loop_syn.adf: $relativePath")
    }
}

Write-Host "PDS: $pdsPath"
Write-Host "GUI Verilog inputs: $($listedVerilog.Count)"
Write-Host "Instantiated local modules found: $($instantiated.Count)"
Write-Host "GUI FIC inputs: $($listedFic.Count)"
foreach ($warning in $warnings) { Write-Warning $warning }
if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Error $message }
    exit 1
}

Write-Host 'PASS: PDS GUI source and FIC registration checks passed.'
