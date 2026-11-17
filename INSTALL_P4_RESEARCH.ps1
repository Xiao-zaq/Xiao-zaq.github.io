param([string]$Workspace='C:\Users\Xiao\Desktop\Four Paper\CODE2\P4_V173_CODE2_WORKSPACE_20261111')
$ErrorActionPreference='Stop'
$target=Join-Path $Workspace '01_ACTIVE_CODE_PACKAGES\P4_RESEARCH_V1'
& (Join-Path $PSScriptRoot 'VERIFY_P4_RESEARCH.ps1') -Root $PSScriptRoot
if(Test-Path -LiteralPath $target){throw 'Target exists. Do not overwrite a previous installation.'}
New-Item -ItemType Directory -Path $target | Out-Null
Get-ChildItem -LiteralPath $PSScriptRoot -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force }
& (Join-Path $target 'VERIFY_P4_RESEARCH.ps1') -Root $target
Write-Host "Installed: $target"
