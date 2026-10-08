# Run locally whenever a new monthly manpower mapping arrives. Writes data/manpower.csv
# (month, team, hashed email, city, status) - no names or plain emails go to the repo.
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
# Logic (agreed with manager): for each month's file -> Department (Field sales = team 0, Inside sales = team 1)
# -> City -> Current Status. Status class: 0 Active, 1 In training (In Training / Newly Hired), 2 Resigned, 3 any other status.
# Only Active + Resigned are counted as SCs; the build also requires the email to appear in the MS to MD tab that month.
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('month,team,hash,city,status')
foreach ($mk in $FILES.Keys) {
  $rows = Import-Csv (Join-Path $Dir $FILES[$mk])
  $n = @{}
  foreach ($r in $rows) {
    $dep = "$($r.Department)".Trim()
    $team = if ($dep -eq 'Field sales') { 0 } elseif ($dep -eq 'Inside sales') { 1 } else { $null }
    if ($null -eq $team) { continue }
    $email = "$($r.'Email ID')".Trim().ToLower(); if (-not $email) { continue }
    $st = "$($r.'Current Status')".Trim()
    $cls = switch -Regex ($st) { '^Active$' { 0 } '^(In Training|Newly Hired)$' { 1 } '^Resigned$' { 2 } default { 3 } }
    $lines.Add("$mk,$team,$(Get-Hash $email),$(Get-City $r.CITY),$cls"); $n[$cls]++
  }
  Write-Host "$mk : active $($n[0]) | training $($n[1]) | resigned $($n[2]) | other status $($n[3])"
}
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
[IO.File]::WriteAllLines([IO.Path]::GetFullPath($Out), $lines, (New-Object Text.UTF8Encoding($false)))
Write-Host "wrote $Out"
