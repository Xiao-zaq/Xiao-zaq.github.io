param([string]$Root=$PSScriptRoot)
$ErrorActionPreference='Stop'
$rows=Import-Csv -LiteralPath (Join-Path $Root 'MANIFEST.csv')
if($rows.Count -eq 0){throw 'Empty manifest'}
foreach($r in $rows){
  if($r.RelativePath.Contains('..') -or $r.RelativePath.Contains(':') -or $r.RelativePath.StartsWith('/')){throw 'Unsafe manifest path'}
  $f=Join-Path $Root $r.RelativePath
  if(!(Test-Path -LiteralPath $f -PathType Leaf)){throw "Missing file: $f"}
  if((Get-Item -LiteralPath $f).Length -ne [long]$r.Bytes){throw "Wrong size: $f"}
  if((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant() -ne $r.SHA256){throw "Wrong hash: $f"}
}
Write-Host "P4 RESEARCH PACKAGE PASS: $($rows.Count)/$($rows.Count)"
