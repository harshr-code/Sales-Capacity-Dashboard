# Builds capacity.json for the Growth Dashboard from the published Raw Data tab (one row per lead) and the MOP tab.
# Runs on Windows PowerShell 5.1 and on pwsh (GitHub Actions, ubuntu). ASCII only.
param(
  [string]$Out = (Join-Path (Join-Path $PSScriptRoot '..') 'capacity.json'),
  [string]$Start = '2026-09-01'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$BASE    = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRUlqvi5njktr8g0lpbagjho4tBxghZIkjRx2WuwfZSLlCoXgvecoFAjludqvN3NKeWP-ZrIU9hiwOY/pub?single=true&output=csv&gid='
$RAW_GID = '1197917477'   # Raw Data: one row per lead
$MOP_GID = '1033353473'   # day-wise MOP for the current month (Cluster, Day, BQL | MS | MD | Order FS | Order IS blocks)
$RAW_HDR = 'Lead_ID,LSQ_City,BQL_Flag,Source_Class,Source_Sub_Class,score,First_Sales_Channel,Sales_Channel,Created_On,lead_delivered_to_lrm,First_Meeting_Schedule_Date,First_Meeting_Done_Date,Order_closure_Date,HoTo_Date,SC_Email_Id'
# Raw Data columns (0-based): 0 Lead_ID, 1 City (B), 2 BQL_Flag (C), 3 Source_Class (D), 4 Source_Sub_Class (E), 5 score (F),
# 6 First_Sales_Channel (G: FS/IS for BQL, MS, MD), 7 Sales_Channel (H: FS/IS for Order, HoTo - kept for later),
# 8 Created_On (I: BQL date), 9 LRM date (J), 10 First MS date (K), 11 First MD date (L), 12 Order date (M), 13 HoTo date (N), 14 SC email (O)

# 24 main cities (Delhi NCR shown city-wise); everything else = Other cities
$CLUSTERS = @('Delhi','Ghaziabad','Noida','Gurgaon','Faridabad','Ahmedabad','Surat','Bangalore','Hyderabad','Amravati','Nagpur','Aurangabad','Nashik','Pune','Kolhapur','Bhopal','Gwalior','Indore','Jabalpur','Jaipur','Kanpur','Lucknow','Varanasi','Chennai')
$ALIAS    = @{ 'New Delhi' = 'Delhi'; 'Gurugram' = 'Gurgaon'; 'Greater Noida' = 'Noida'; 'Bengaluru' = 'Bangalore'; 'Banglore' = 'Bangalore' }
$CHANNELS = @('Digital','Referral','BTL','SolarPro','Others')
$BANDS    = @('Excellent (9-10)','Good (7-9)','Average (5-7)','Poor (<5)','No score')
$TEAMS    = @('Field Sales','Inside Sales','Unassigned')
$INV      = [Globalization.CultureInfo]::InvariantCulture
[string[]]$DFMT = 'd-MMM-yy', 'dd-MMM-yy'

function Get-Date2($s) {
  $d = [datetime]::MinValue
  if ($s -and [datetime]::TryParseExact($s.Trim(), $DFMT, $INV, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
  return $null
}
# Only the 24 main cities are kept (PAN = their total). Any other city, blank, Invalid or Inactive returns -1 and is left out.
$cityIdx = @{}; for ($i = 0; $i -lt $CLUSTERS.Count; $i++) { $cityIdx[$CLUSTERS[$i]] = $i }
function Get-CityIdx($s) {
  $s = "$s".Trim(); if ($ALIAS.ContainsKey($s)) { $s = $ALIAS[$s] }
  if ($cityIdx.ContainsKey($s)) { return $cityIdx[$s] } else { return -1 }
}
# Channel from Col D: Digital, Referral, SolarPro as is; "BTL Activity" -> BTL; Referral with sub-channel BTL -> BTL
# (sub-channel "BTL Referral"); every other source -> Others. Sub-channel from Col E as is.
function Get-ChIdx($cls, $sub) {
  switch ("$cls".Trim()) {
    'Digital'      { return 0 }
    'Referral'     { if ("$sub".Trim() -eq 'BTL') { return 2 } else { return 1 } }
    'BTL Activity' { return 2 }
    'BTL'          { return 2 }
    'SolarPro'     { return 3 }
    default        { return 4 }
  }
}
$SUBS = New-Object System.Collections.Generic.List[string]; $SUBCH = New-Object System.Collections.Generic.List[int]; $subIdx = @{}
function Get-SubIdx($ch, $cls, $sub) {
  $n = ("$sub".Trim() -replace '["\\]', ''); if (-not $n) { $n = ("$cls".Trim() -replace '["\\]', ''); if (-not $n) { $n = '(blank)' } }
  if ("$cls".Trim() -eq 'Referral' -and $n -eq 'BTL') { $n = 'BTL Referral' }
  $k = "$ch|$n"
  if (-not $subIdx.ContainsKey($k)) { $subIdx[$k] = $SUBS.Count; $SUBS.Add($n); $SUBCH.Add($ch) }
  return $subIdx[$k]
}
function Get-Band($s) {
  $v = 0.0
  if (-not "$s".Trim() -or -not [double]::TryParse("$s".Trim(), [Globalization.NumberStyles]::Float, $INV, [ref]$v)) { return 4 }
  if ($v -gt 9) { 0 } elseif ($v -gt 7) { 1 } elseif ($v -gt 5) { 2 } else { 3 }
}
function Get-Team($s) { switch ("$s".Trim()) { 'Field Sales' { 0 } 'Inside Sales' { 1 } default { 2 } } }

# ---- download + parse Raw Data (proper CSV parsing; guard header and row count) ----
$rawTmp = [IO.Path]::GetTempFileName()
Invoke-WebRequest ($BASE + $RAW_GID) -UseBasicParsing -OutFile $rawTmp
Add-Type -AssemblyName Microsoft.VisualBasic
$tp = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($rawTmp)
$tp.TextFieldType = 'Delimited'; $tp.SetDelimiters(','); $tp.HasFieldsEnclosedInQuotes = $true
$hdr = ($tp.ReadFields() -join ',').TrimStart([char]0xFEFF).Trim().TrimEnd(',')   # empty trailing columns in the sheet are ignored
if ($hdr -ne $RAW_HDR) { $tp.Close(); throw "Raw Data header changed.`nExpected: $RAW_HDR`nGot:      $hdr" }
$rows = New-Object System.Collections.Generic.List[object]
while (-not $tp.EndOfData) { $rows.Add($tp.ReadFields()) }
$tp.Close(); Remove-Item $rawTmp
if ($rows.Count -lt 10000) { throw "Raw Data has only $($rows.Count) rows - refusing to publish" }
Write-Host "Raw Data : $($rows.Count) rows"

# Parse each row once: [c, ch, sb, b, t, bqlFlag, created, lrm, ms, md, email]
$LEADS = New-Object System.Collections.Generic.List[object]
foreach ($f in $rows) {
  $ch = Get-ChIdx $f[3] $f[4]
  $LEADS.Add(@((Get-CityIdx $f[1]), $ch, (Get-SubIdx $ch $f[3] $f[4]), (Get-Band $f[5]), (Get-Team $f[6]), ("$($f[2])".Trim() -eq '1'),
    (Get-Date2 $f[8]), (Get-Date2 $f[9]), (Get-Date2 $f[10]), (Get-Date2 $f[11]), "$($f[14])".Trim().ToLower(),
    (Get-Date2 $f[13]), (Get-Team $f[7])))   # [11] HoTo date (Col N), [12] last sales channel (Col H) - used for HoTo
}
$rows = $null

# As-of = last COMPLETE day, never later than yesterday IST: the latest day that has meeting-done data AND whose BQL
# is at least half the median daily BQL of the 7 days before it. A day the source has only partly loaded is left out.
$lastFull = [datetime]::UtcNow.AddHours(5.5).Date.AddDays(-1)
$bqlDay = @{}; $mdMax = [datetime]::MinValue
foreach ($ld in $LEADS) {
  if ($ld[5] -and $ld[6] -and $ld[6] -le $lastFull) { $k = $ld[6].ToString('yyyy-MM-dd'); if ($bqlDay.ContainsKey($k)) { $bqlDay[$k]++ } else { $bqlDay[$k] = 1 } }
  if ($ld[9] -and $ld[9] -gt $mdMax -and $ld[9] -le $lastFull) { $mdMax = $ld[9] }
}
if ($mdMax -eq [datetime]::MinValue) { throw 'No meeting-done dates found' }
$asOf = $mdMax
while ($true) {
  $prev = @(1..7 | ForEach-Object { $k = $asOf.AddDays(-$_).ToString('yyyy-MM-dd'); if ($bqlDay.ContainsKey($k)) { $bqlDay[$k] } else { 0 } } | Sort-Object)
  $med = $prev[3]; $today = $bqlDay[$asOf.ToString('yyyy-MM-dd')]; if (-not $today) { $today = 0 }
  if ($med -eq 0 -or $today -ge 0.5 * $med) { break }
  Write-Host "NOTE: $($asOf.ToString('dd MMM')) looks incomplete in the source (BQL $today vs typical $med) - dashboard runs to the day before"
  $asOf = $asOf.AddDays(-1)
}
$startD = [datetime]::ParseExact($Start, 'yyyy-MM-dd', $INV)
$endD   = (New-Object DateTime($asOf.Year, $asOf.Month, 1)).AddMonths(1).AddDays(-1)
$asOfLm = $asOf.AddMonths(-1)   # fair LMTD: last month's cohort only counts events up to the same day last month

$dates = New-Object System.Collections.Generic.List[string]; $dIdx = @{}
for ($d = $startD; $d -le $endD; $d = $d.AddDays(1)) { $k = $d.ToString('yyyy-MM-dd'); $dIdx[$k] = $dates.Count; $dates.Add($k) }

# ---- SC roster (data/manpower.csv, built locally by build-manpower.ps1) ----
$mpPath = Join-Path (Join-Path $PSScriptRoot '..') 'data/manpower.csv'
$mp = @(Import-Csv $mpPath)
if ($mp.Count -lt 100) { throw "manpower.csv has only $($mp.Count) rows" }
$mpMonths = @($mp | ForEach-Object { $_.month } | Sort-Object -Unique)
$months = @($dates | ForEach-Object { $_.Substring(0, 7) } | Sort-Object -Unique)
$sha = [Security.Cryptography.SHA256]::Create()
function Get-Hash($e) { (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($e)) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 20) }
# Roster per month: hash -> [team (manpower Department), cityIdx (manpower city), status class]
$roster = @{}; $rosterFrom = @(); $present = @{}
for ($mi = 0; $mi -lt $months.Count; $mi++) {
  $mk = $months[$mi]
  $src = @($mpMonths | Where-Object { $_ -le $mk } | Select-Object -Last 1)[0]
  if (-not $src) { $src = $mpMonths[0] }
  $rosterFrom += $src
  $map = @{}
  foreach ($r in $mp) { if ($r.month -eq $src) { $map[$r.hash] = @([int]$r.team, (Get-CityIdx $r.city), [int]$r.status) } }
  $roster[$mk] = $map; $present[$mk] = @{}
}

# ---- Effort view: every lead, each stage on its own date ----
# m:   d|c|ch|sub|b|t|k -> [MS, MD]   MS on First_Meeting_Schedule_Date (future slots kept to month end), MD on First_Meeting_Done_Date
#      k = class of the SC (Col O) in that month's manpower file: 0 Active, 1 In training, 2 Resigned, 3 Other SC, 4 No SC email
# bql: d|c|ch|sub|b|t -> [BQL, LRM]   BQL on Created_On where BQL_Flag = 1; LRM on its own date (Col J)
# ho:  d|c|ch|sub|b|t -> HoTo        HoTo on HoTo_Date (Col N); t = last sales channel (Col H)
$m = @{}; $bqlAgg = @{}; $ho = @{}; $hashCache = @{}
function Add-M($dt, $p, $h, $slot) {
  $mk = $dt.ToString('yyyy-MM'); $k = 4
  if ($h) {
    $k = 3
    if ($roster[$mk].ContainsKey($h) -and $roster[$mk][$h][2] -le 2) { $k = $roster[$mk][$h][2] }
    $present[$mk][$h] = 1
  }
  $key = "$($dIdx[$dt.ToString('yyyy-MM-dd')])|$($p[0])|$($p[1])|$($p[2])|$($p[3])|$($p[4])|$k"
  if (-not $m.ContainsKey($key)) { $m[$key] = @(0, 0) }; $m[$key][$slot]++
}
function Add-B($dt, $p, $slot) {
  $key = "$($dIdx[$dt.ToString('yyyy-MM-dd')])|$($p[0])|$($p[1])|$($p[2])|$($p[3])|$($p[4])"
  if (-not $bqlAgg.ContainsKey($key)) { $bqlAgg[$key] = @(0, 0) }; $bqlAgg[$key][$slot]++
}
# ---- Cohort: BQL leads by Created_On; each later stage bucketed by month offset (0 = M0, 1 = M1, 2 = M2) ----
# coh: d|c|ch|b|t|stage|off|early -> n    stage 0 LRM, 1 MS, 2 MD; early = event on/before the same day last month (for fair LMTD)
$coh = @{}
function Add-C($p, $cd, $stage, $ev) {
  if (-not $ev -or $ev -gt $asOf) { return }
  $off = ($ev.Year - $cd.Year) * 12 + $ev.Month - $cd.Month
  if ($off -lt 0) { $off = 0 }; if ($off -gt 2) { return }
  $early = if ($ev -le $asOfLm) { 1 } else { 0 }
  $key = "$($dIdx[$cd.ToString('yyyy-MM-dd')])|$($p[0])|$($p[1])|$($p[3])|$($p[4])|$stage|$off|$early"
  if ($coh.ContainsKey($key)) { $coh[$key]++ } else { $coh[$key] = 1 }
}
foreach ($ld in $LEADS) {
  if ($ld[0] -lt 0) { continue }   # lead not in the 24 main cities
  $h = ''
  if ($ld[10]) { if (-not $hashCache.ContainsKey($ld[10])) { $hashCache[$ld[10]] = Get-Hash $ld[10] }; $h = $hashCache[$ld[10]] }
  $cd = $ld[6]; $inBql = $ld[5] -and $cd -and $cd -ge $startD -and $cd -le $asOf
  if ($inBql) { Add-B $cd $ld 0; Add-C $ld $cd 0 $ld[7]; Add-C $ld $cd 1 $ld[8]; Add-C $ld $cd 2 $ld[9] }
  if ($ld[7] -and $ld[7] -ge $startD -and $ld[7] -le $asOf) { Add-B $ld[7] $ld 1 }
  if ($ld[8] -and $ld[8] -ge $startD -and $ld[8] -le $endD) { Add-M $ld[8] $ld $h 0 }
  if ($ld[9] -and $ld[9] -ge $startD -and $ld[9] -le $asOf) { Add-M $ld[9] $ld $h 1 }
  # HoTo on its own date (Col N), Field / Inside from the last sales channel (Col H)
  if ($ld[11] -and $ld[11] -ge $startD -and $ld[11] -le $asOf) {
    $key = "$($dIdx[$ld[11].ToString('yyyy-MM-dd')])|$($ld[0])|$($ld[1])|$($ld[2])|$($ld[3])|$($ld[12])"
    if ($ho.ContainsKey($key)) { $ho[$key]++ } else { $ho[$key] = 1 }
  }
}

# SC count rows mi|c|team|class: everyone tagged SC in that month's manpower file (Field sales SC / Sr SC, Inside sales SC),
# by status class. City and team come from the manpower file. The dashboard counts Active (class 0) only.
$rost = @{}
for ($mi = 0; $mi -lt $months.Count; $mi++) {
  $mk = $months[$mi]
  foreach ($h in $roster[$mk].Keys) {
    $rp = $roster[$mk][$h]; if ($rp[2] -gt 2 -or $rp[1] -lt 0) { continue }   # SC's manpower city must be a main city
    $k = "$mi|$($rp[1])|$($rp[0])|$($rp[2])"
    if ($rost.ContainsKey($k)) { $rost[$k]++ } else { $rost[$k] = 1 }
  }
  $a = 0; foreach ($kk in $rost.Keys) { if ($kk -like "$mi|*|0|0") { $a += $rost[$kk] } }
  Write-Host "$mk Active Field SCs (24 cities): $a (from $($rosterFrom[$mi]) file)"
}

# ---- MOP: rows [cityIdx, day, metric, chIdx, value]; metric 0 BQL, 1 MS, 2 MD (FS+Insta), 3 Order (FS) ----
# MOP tab (layout from 13 Oct 2026): A Cluster, B Day; then per metric the columns below (0-based), channel order
# Digital, Referral, BTL, SolarPro, Others. Each channel can be the sum of several sub-columns.
$MOPMAP = @(
  @{m = 0; ch = @(@(6), @(8, 9), @(14, 15), @(11, 12), @(16)) }     # BQL: G | I+J | O+P | L+M | Q (IVR)
  @{m = 1; ch = @(@(19), @(21, 22), @(27, 28), @(24, 25), @(29)) }  # MS:  T | V+W | AB+AC | Y+Z | AD (IVR)
  @{m = 2; ch = @(@(33, 34), @(36, 37), @(42, 43), @(39, 40), @(44)) }  # MD: AH+AI | AK+AL | AQ+AR | AN+AO | AS (IVR)
  @{m = 3; ch = @(@(48), @(50, 51), @(56, 57), @(53, 54), @()) }    # Order FS: AW | AY+AZ | BE+BF | BB+BC (kept for later)
)
$mopTmp = [IO.Path]::GetTempFileName()
Invoke-WebRequest ($BASE + $MOP_GID) -UseBasicParsing -OutFile $mopTmp
$mp2 = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($mopTmp)
$mp2.TextFieldType = 'Delimited'; $mp2.SetDelimiters(','); $mp2.HasFieldsEnclosedInQuotes = $true
$ml = New-Object System.Collections.Generic.List[object]
while (-not $mp2.EndOfData) { $ml.Add($mp2.ReadFields()) }
$mp2.Close(); Remove-Item $mopTmp
$mopRows = New-Object System.Collections.Generic.List[string]
# If the MOP tab's layout changes, skip MOP (the MOP tab then shows "no MOP") instead of stopping the whole refresh
$h1 = $ml[0]; $h2 = $ml[1]; $h3 = $ml[2]
$mopOk = $h1[5] -eq 'BQL' -and $h1[18] -eq 'MS' -and $h1[31] -like 'MD*' -and $h1[46] -eq 'ORDER (FS)' -and $h2[6] -eq 'Digital' -and $h2[19] -eq 'Digital' -and $h3[0] -eq 'Cluster' -and $h3[1] -eq 'Day'
if (-not $mopOk) { Write-Host "NOTE: MOP tab layout changed - MOP skipped until the build is updated. Header: $($h1 -join ',')" }
function Get-Num($s) { $v = 0.0; if ([double]::TryParse(("$s".Trim() -replace ',', ''), [Globalization.NumberStyles]::Float, $INV, [ref]$v)) { $v } else { 0 } }
$maxDay = 0
if ($mopOk) {
  for ($i = 3; $i -lt $ml.Count; $i++) {
    $q = $ml[$i]
    $day = 0; if (-not [int]::TryParse("$($q[1])".Trim(), [ref]$day)) { continue }
    if ($day -gt $maxDay) { $maxDay = $day }
    $c = Get-CityIdx $q[0]; if ($c -lt 0) { continue }   # MOP only for the main cities
    foreach ($mm in $MOPMAP) {
      for ($k = 0; $k -lt 5; $k++) {
        $v = 0.0; foreach ($col in $mm.ch[$k]) { $v += Get-Num $q[$col] }
        if ($v) { $mopRows.Add("[$c,$day,$($mm.m),$k,$v]") }
      }
    }
  }
}
# Guard against last month's MOP being tagged to a new month: day count must match the as-of month
if ($maxDay -ne [datetime]::DaysInMonth($asOf.Year, $asOf.Month)) {
  Write-Host "NOTE: MOP tab has $maxDay days but $($asOf.ToString('MMM yyyy')) has $([datetime]::DaysInMonth($asOf.Year, $asOf.Month)) - MOP skipped until the tab is updated"
  $mopRows.Clear()
}
Write-Host "MOP tab : $($mopRows.Count) values for $($asOf.ToString('yyyy-MM'))"

# ---- write JSON ----
function Join-Q($arr) { ($arr | ForEach-Object { '"' + $_ + '"' }) -join ',' }
function Join-Rows($h, [scriptblock]$val) { ($h.Keys | ForEach-Object { '[' + ($_ -replace '\|', ',') + ',' + (& $val $h[$_]) + ']' }) -join ',' }
$sb = New-Object Text.StringBuilder
[void]$sb.Append('{"asOf":"' + $asOf.ToString('yyyy-MM-dd') + '","asOfLm":"' + $asOfLm.ToString('yyyy-MM-dd') + '","generated":"' + [datetime]::UtcNow.AddHours(5.5).ToString('yyyy-MM-dd HH:mm') + ' IST"')
[void]$sb.Append(',"dates":[' + (Join-Q $dates) + '],"cities":[' + (Join-Q $CLUSTERS) + '],"channels":[' + (Join-Q $CHANNELS) + '],"bands":[' + (Join-Q $BANDS) + '],"teams":[' + (Join-Q $TEAMS) + ']')
[void]$sb.Append(',"m":[' + (Join-Rows $m { param($v) "$($v[0]),$($v[1])" }) + ']')
[void]$sb.Append(',"subs":[' + (Join-Q $SUBS) + '],"subCh":[' + ($SUBCH -join ',') + ']')
[void]$sb.Append(',"months":[' + (Join-Q $months) + '],"rosterFrom":[' + (Join-Q $rosterFrom) + ']')
[void]$sb.Append(',"rost":[' + (Join-Rows $rost { param($v) "$v" }) + ']')
[void]$sb.Append(',"mop":{"month":"' + $asOf.ToString('yyyy-MM') + '","rows":[' + ($mopRows -join ',') + ']}')
[void]$sb.Append(',"coh":[' + (Join-Rows $coh { param($v) "$v" }) + ']')
[void]$sb.Append(',"ho":[' + (Join-Rows $ho { param($v) "$v" }) + ']')
[void]$sb.Append(',"bql":[' + (Join-Rows $bqlAgg { param($v) "$($v[0]),$($v[1])" }) + ']}')
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out), $sb.ToString(), (New-Object Text.UTF8Encoding($false)))

$totMs = 0; $totMd = 0; foreach ($v in $m.Values) { $totMs += $v[0]; $totMd += $v[1] }
$totB = 0; $totL = 0; foreach ($v in $bqlAgg.Values) { $totB += $v[0]; $totL += $v[1] }
$totH = 0; foreach ($v in $ho.Values) { $totH += $v }; Write-Host "HoTo: $totH"
Write-Host ("As of {0} | BQL {1} | LRM {2} | MS {3} | MD {4} | cohort rows {5} | wrote {6} ({7:N0} KB)" -f $asOf.ToString('dd MMM yyyy'), $totB, $totL, $totMs, $totMd, $coh.Count, $Out, ((Get-Item $Out).Length / 1KB))
