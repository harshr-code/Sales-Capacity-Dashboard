# Run locally whenever a new monthly manpower mapping arrives. Writes data/manpower.csv
# (month, team, hashed email, city, DOJ, resigned) - no names or plain emails go to the repo.
param(
  [string]$Dir = 'C:\Users\User\Downloads',
  [string]$Out = (Join-Path (Join-Path $PSScriptRoot '..') 'data\manpower.csv')
)
$ErrorActionPreference = 'Stop'
$INV = [Globalization.CultureInfo]::InvariantCulture
# month key -> file. Add a line per new month.
$FILES = [ordered]@{
  '2026-07' = "Manpower Data (Sales_PreSales_Inside sales_BTL) -October'26 -  July Mapping.csv"
  '2026-08' = "Manpower Data (Sales_PreSales_Inside sales_BTL) -October'26 - August Mapping.csv"
  '2026-09' = "Manpower Data (Sales_PreSales_Inside sales_BTL) -October'26 - September Mapping.csv"
  '2026-10' = "Manpower Data (Sales_PreSales_Inside sales_BTL) -October'26 - October Mapping.csv"
}
$sha = [Security.Cryptography.SHA256]::Create()
function Get-Hash($e) { (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($e)) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 20) }
function Get-City($s) {
  $s = "$s".Trim()
  if ($s -match '^(banglore|bengaluru|bangalore)$') { return 'Bangalore' }
  if ($s -match '^(new delhi|delhi)$') { return 'Delhi' }
  if ($s -match '^(noida|greater noida)$') { return 'Noida' }
  if ($s -match '^(gurgaon|gurugram)$') { return 'Gurgaon' }
  if ($s -match '^delhi ncr$') { return 'Delhi NCR (unsplit)' }
  if ($s -match '^aurangabad|^chhatrapati') { return 'Aurangabad' }
  return (Get-Culture).TextInfo.ToTitleCase($s.ToLower())
}
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('month,team,hash,city,doj,resigned')
foreach ($mk in $FILES.Keys) {
  $rows = Import-Csv (Join-Path $Dir $FILES[$mk])
  $n = 0
  foreach ($r in $rows) {
    $dep = "$($r.Department)".Trim(); $des = "$($r.Designation)".Trim()
    $team = $null
    if ($dep -eq 'Field sales' -and ($des -eq 'SC' -or $des -eq 'Sr SC')) { $team = 0 }
    elseif ($dep -eq 'Inside sales' -and $des -eq 'SC') { $team = 1 }
    if ($null -eq $team) { continue }
    $email = "$($r.'Email ID')".Trim().ToLower(); if (-not $email) { continue }
    $doj = [datetime]::MinValue
    [string[]]$fmts = 'dd-MMM-yy', 'd-MMM-yy', 'dd-MMM-yyyy', 'd-MMM-yyyy', 'dd MMM yyyy', 'd MMM yyyy', 'dd/MM/yyyy', 'd/M/yyyy'
    $ok = [datetime]::TryParseExact("$($r.'Date of Joining')".Trim(), $fmts, $INV, [Globalization.DateTimeStyles]::None, [ref]$doj)
    $ten = 0
    if (-not $ok -and [int]::TryParse("$($r.Tenure)".Trim(), [ref]$ten)) {   # fallback: Tenure days as of file date
      $doj = (Get-Item (Join-Path $Dir $FILES[$mk])).LastWriteTime.Date.AddDays(-$ten); $ok = $true
    }
    $dojS = if ($ok) { $doj.ToString('yyyy-MM-dd') } else { '' }   # blank DOJ -> treated as Active
    $res = if ("$($r.'Current Status')".Trim() -eq 'Resigned') { 1 } else { 0 }
    $lines.Add("$mk,$team,$(Get-Hash $email),$(Get-City $r.CITY),$dojS,$res"); $n++
  }
  Write-Host "$mk : $n SCs"
}
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
[IO.File]::WriteAllLines([IO.Path]::GetFullPath($Out), $lines, (New-Object Text.UTF8Encoding($false)))
Write-Host "wrote $Out"
