# Builds capacity.json for the Sales Capacity dashboard from the two published sheet tabs.
# Runs on Windows PowerShell 5.1 and on pwsh (GitHub Actions, ubuntu). ASCII only.
param(
  [string]$Out = (Join-Path (Join-Path $PSScriptRoot '..') 'capacity.json'),
  [string]$Start = '2026-09-01'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$BASE    = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRUlqvi5njktr8g0lpbagjho4tBxghZIkjRx2WuwfZSLlCoXgvecoFAjludqvN3NKeWP-ZrIU9hiwOY/pub?single=true&output=csv&gid='
$MS_GID  = '0'
$BQL_GID = '111764591'
$MOP_GID = '1033353473'   # day-wise MOP for the current month (Cluster, Day, BQL | MS | MD | Order FS | Order IS blocks)
$MS_HDR  = 'Lead_ID,City,Source_Class_Final,Source_Sub_Class_Final,Current_SC_Email,Current_Sales_Channel,Last_Meeting_Schedule_Date,Last_Meeting_Done_Date,Score,Channel'
$BQL_HDR = 'Action_Date,CITY,Source_Class_final,bill_qualified,score,Channel Filter'

$CLUSTERS = @('Agra','Ahmedabad','Amravati','Aurangabad','Bangalore','Bhopal','Chennai','Coimbatore','Delhi NCR','Gwalior','Hyderabad','Indore','Jabalpur','Jaipur','Jalgaon','Kanpur','Kolhapur','Lucknow','Nagpur','Nashik','Pune','Solapur','Varanasi')
$NCR      = @('Delhi','Noida','Ghaziabad','Gurgaon','Faridabad')
$CHANNELS = @('Digital','Referral','BTL','SolarPro','Others')
$BANDS    = @('Excellent (9-10)','Good (7-9)','Average (5-7)','Poor (<5)','No score')
$TEAMS    = @('Field Sales','Inside Sales','Unassigned')
$INV      = [Globalization.CultureInfo]::InvariantCulture

function Get-Tab($gid, $hdr, $name) {
  $tmp = [IO.Path]::GetTempFileName()
  Invoke-WebRequest ($BASE + $gid) -UseBasicParsing -OutFile $tmp
  $sr = New-Object IO.StreamReader($tmp); $first = $sr.ReadLine(); $sr.Close()
  $first = $first.TrimStart([char]0xFEFF).Trim()
  if ($first -ne $hdr) { throw "$name header changed.`nExpected: $hdr`nGot:      $first" }
  $rows = @(Import-Csv $tmp); Remove-Item $tmp
  if ($rows.Count -lt 1000) { throw "$name has only $($rows.Count) rows - refusing to publish" }
  Write-Host "$name : $($rows.Count) rows"
  return ,$rows
}
function Get-Date2($s) {
  $d = [datetime]::MinValue
  if ($s -and [datetime]::TryParseExact($s.Trim(), 'dd/MM/yyyy', $INV, 'None', [ref]$d)) { return $d }
  return $null
}
$cityIdx = @{}; for ($i = 0; $i -lt $CLUSTERS.Count; $i++) { $cityIdx[$CLUSTERS[$i]] = $i }
function Get-CityIdx($s) {
  $s = "$s".Trim(); if ($NCR -contains $s) { $s = 'Delhi NCR' }
  if ($cityIdx.ContainsKey($s)) { return $cityIdx[$s] } else { return -1 }
}
function Get-ChIdx($s) { $i = [array]::IndexOf($CHANNELS, "$s".Trim()); if ($i -lt 0) { 4 } else { $i } }
function Get-Band($s) {
  $v = 0.0
  if (-not "$s".Trim() -or -not [double]::TryParse("$s".Trim(), [Globalization.NumberStyles]::Float, $INV, [ref]$v)) { return 4 }
  if ($v -gt 9) { 0 } elseif ($v -gt 7) { 1 } elseif ($v -gt 5) { 2 } else { 3 }
}
function Get-Team($s) { switch ("$s".Trim()) { 'Field Sales' { 0 } 'Inside Sales' { 1 } default { 2 } } }

$ms  = Get-Tab $MS_GID  $MS_HDR  'MS to MD tab'
$bq  = Get-Tab $BQL_GID $BQL_HDR 'BQL tab'

# As-of = latest meeting-done date, capped at yesterday IST (today is a partial day; its slots count as booked ahead)
$lastFull = [datetime]::UtcNow.AddHours(5.5).Date.AddDays(-1)
$asOf = [datetime]::MinValue
foreach ($r in $ms) { $d = Get-Date2 $r.Last_Meeting_Done_Date; if ($d -and $d -gt $asOf -and $d -le $lastFull) { $asOf = $d } }
if ($asOf -eq [datetime]::MinValue) { throw 'No meeting-done dates found' }
$startD = [datetime]::ParseExact($Start, 'yyyy-MM-dd', $INV)
$endD   = (New-Object DateTime($asOf.Year, $asOf.Month, 1)).AddMonths(1).AddDays(-1)

$dates = New-Object System.Collections.Generic.List[string]; $dIdx = @{}
for ($d = $startD; $d -le $endD; $d = $d.AddDays(1)) { $k = $d.ToString('yyyy-MM-dd'); $dIdx[$k] = $dates.Count; $dates.Add($k) }

# SC roster from data/manpower.csv (built locally by build-manpower.ps1). Each month uses its own mapping,
# or the latest earlier mapping if that month's file is not loaded yet (tenure re-checked on the 1st).
# SC class: 0 Active (>=30 days on the 1st), 1 In training, 2 Resigned. Meeting-side extra classes: 3 Other SC, 4 No SC email.
$mpPath = Join-Path (Join-Path $PSScriptRoot '..') 'data/manpower.csv'
$mp = @(Import-Csv $mpPath)
if ($mp.Count -lt 100) { throw "manpower.csv has only $($mp.Count) rows" }
$mpMonths = @($mp | ForEach-Object { $_.month } | Sort-Object -Unique)
$months = @($dates | ForEach-Object { $_.Substring(0, 7) } | Sort-Object -Unique)
$sha = [Security.Cryptography.SHA256]::Create()
function Get-Hash($e) { (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($e)) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 20) }
$roster = @{}; $rosterFrom = @(); $rost = @{}
for ($mi = 0; $mi -lt $months.Count; $mi++) {
  $mk = $months[$mi]
  $src = @($mpMonths | Where-Object { $_ -le $mk } | Select-Object -Last 1)[0]
  if (-not $src) { $src = $mpMonths[0] }
  $rosterFrom += $src
  $first = [datetime]::ParseExact($mk + '-01', 'yyyy-MM-dd', $INV)
  $map = @{}
  foreach ($r in $mp) {
    if ($r.month -ne $src) { continue }
    $cls = 0
    if ($r.resigned -eq '1') { $cls = 2 }
    elseif ($r.doj -and ($first - [datetime]::ParseExact($r.doj, 'yyyy-MM-dd', $INV)).Days -lt 30) { $cls = 1 }
    $t = [int]$r.team
    $map["$($r.hash)|$t"] = $cls
    $c = Get-CityIdx $r.city
    if ($c -ge 0) { $k = "$mi|$c|$t|$cls"; if ($rost.ContainsKey($k)) { $rost[$k]++ } else { $rost[$k] = 1 } }
  }
  $roster[$mk] = $map
}

# Meetings: key d|c|ch|b|t|k -> [ms, md]. MS on slot date (future slots kept to month end), MD on done date (to as-of).
# k = SC class of the lead's current SC in the manpower mapping of the meeting's month.
$m = @{}; $hashCache = @{}
function Add-M($dt, $c, $ch, $b, $t, $h, $slot) {
  $mk = $dt.ToString('yyyy-MM'); $k = 4
  if ($h) { $hk = "$h|$t"; if ($roster[$mk].ContainsKey($hk)) { $k = $roster[$mk][$hk] } else { $k = 3 } }
  $key = "$($dIdx[$dt.ToString('yyyy-MM-dd')])|$c|$ch|$b|$t|$k"
  if (-not $m.ContainsKey($key)) { $m[$key] = @(0, 0) }; $m[$key][$slot]++
}
foreach ($r in $ms) {
  $c = Get-CityIdx $r.City; if ($c -lt 0) { continue }
  $ch = Get-ChIdx $r.Channel; $b = Get-Band $r.Score; $t = Get-Team $r.Current_Sales_Channel
  $email = "$($r.Current_SC_Email)".Trim().ToLower()
  $h = ''
  if ($email) { if (-not $hashCache.ContainsKey($email)) { $hashCache[$email] = Get-Hash $email }; $h = $hashCache[$email] }
  $msd = Get-Date2 $r.Last_Meeting_Schedule_Date
  $mdd = Get-Date2 $r.Last_Meeting_Done_Date
  if ($msd -and $msd -ge $startD -and $msd -le $endD) { Add-M $msd $c $ch $b $t $h 0 }
  if ($mdd -and $mdd -ge $startD -and $mdd -le $asOf) { Add-M $mdd $c $ch $b $t $h 1 }
}

# BQL: key d|c|ch|b -> SUM(bill_qualified), only rows with bill_qualified > 0
$bqlAgg = @{}
foreach ($r in $bq) {
  $v = 0; if (-not [int]::TryParse("$($r.bill_qualified)".Trim(), [ref]$v) -or $v -le 0) { continue }
  $c = Get-CityIdx $r.CITY; if ($c -lt 0) { continue }
  $d = Get-Date2 $r.Action_Date; if (-not $d -or $d -lt $startD -or $d -gt $endD) { continue }
  $k = "$($dIdx[$d.ToString('yyyy-MM-dd')])|$c|$(Get-ChIdx $r.'Channel Filter')|$(Get-Band $r.score)"
  if ($bqlAgg.ContainsKey($k)) { $bqlAgg[$k] += $v } else { $bqlAgg[$k] = $v }
}

# MOP: rows [cityIdx, day, metric, chIdx, value]; metric 0 BQL, 1 MS, 2 MD (FS+Insta), 3 Order FS, 4 Order IS (ch 5 = total).
# Tagged with the as-of month. Column positions are guarded on the two header rows.
$mopTmp = [IO.Path]::GetTempFileName()
Invoke-WebRequest ($BASE + $MOP_GID) -UseBasicParsing -OutFile $mopTmp
$ml = [IO.File]::ReadAllLines($mopTmp); Remove-Item $mopTmp
$h1 = $ml[0] -split ','; $h2 = $ml[1] -split ','
if ($h1[3] -ne 'BQL' -or $h1[10] -ne 'MS' -or $h1[17] -notlike 'MD*' -or $h1[24] -ne 'ORDER (FS)' -or $h1[33] -ne 'ORDER (IS)' -or $h2[25] -ne 'Total FS') { throw "MOP tab layout changed: $($ml[0])" }
$mopRows = New-Object System.Collections.Generic.List[string]
# block start col -> channel cols in order Digital, Referral, SolarPro, BTL, then extra cols that roll into Others
# Others = block Total - (Digital + Referral + SolarPro + BTL), so channels always add up to the sheet's Total (covers IVR, EC Direct, rounding)
$blocks = @(@{m = 0; s = 4; t = 3 }, @{m = 1; s = 11; t = 10 }, @{m = 2; s = 18; t = 17 })   # orders not tracked
$chOrder = @(0, 1, 3, 2)   # Digital, Referral, SolarPro->idx3, BTL->idx2
function Get-Num($s) { $v = 0.0; if ([double]::TryParse("$s".Trim(), [Globalization.NumberStyles]::Float, $INV, [ref]$v)) { $v } else { 0 } }
for ($i = 3; $i -lt $ml.Count; $i++) {
  $p = $ml[$i] -split ','
  $c = Get-CityIdx $p[0]; if ($c -lt 0) { continue }
  $day = 0; if (-not [int]::TryParse($p[1], [ref]$day)) { continue }
  foreach ($bk in $blocks) {
    $o = Get-Num $p[$bk.t]
    for ($j = 0; $j -lt 4; $j++) { $v = Get-Num $p[$bk.s + $j]; $o -= $v; if ($v) { $mopRows.Add("[$c,$day,$($bk.m),$($chOrder[$j]),$v]") } }
    if ($o) { $mopRows.Add("[$c,$day,$($bk.m),4,$o]") }
  }
}
# Guard against last month's MOP being tagged to a new month: day count must match the as-of month
$maxDay = 0; for ($i = 3; $i -lt $ml.Count; $i++) { $dd = 0; if ([int]::TryParse(($ml[$i] -split ',')[1], [ref]$dd) -and $dd -gt $maxDay) { $maxDay = $dd } }
if ($maxDay -ne [datetime]::DaysInMonth($asOf.Year, $asOf.Month)) {
  Write-Host "NOTE: MOP tab has $maxDay days but $($asOf.ToString('MMM yyyy')) has $([datetime]::DaysInMonth($asOf.Year, $asOf.Month)) - MOP skipped until the tab is updated"
  $mopRows.Clear()
}
Write-Host "MOP tab : $($mopRows.Count) values for $($asOf.ToString('yyyy-MM'))"

function Join-Q($arr) { ($arr | ForEach-Object { '"' + $_ + '"' }) -join ',' }
$sb = New-Object Text.StringBuilder
[void]$sb.Append('{"asOf":"' + $asOf.ToString('yyyy-MM-dd') + '","generated":"' + [datetime]::UtcNow.AddHours(5.5).ToString('yyyy-MM-dd HH:mm') + ' IST"')
[void]$sb.Append(',"dates":[' + (Join-Q $dates) + '],"cities":[' + (Join-Q $CLUSTERS) + '],"channels":[' + (Join-Q $CHANNELS) + '],"bands":[' + (Join-Q $BANDS) + '],"teams":[' + (Join-Q $TEAMS) + ']')
[void]$sb.Append(',"m":[' + (($m.Keys | ForEach-Object { '[' + ($_ -replace '\|', ',') + ',' + $m[$_][0] + ',' + $m[$_][1] + ']' }) -join ',') + ']')
[void]$sb.Append(',"months":[' + (Join-Q $months) + '],"rosterFrom":[' + (Join-Q $rosterFrom) + ']')
[void]$sb.Append(',"rost":[' + (($rost.Keys | ForEach-Object { '[' + ($_ -replace '\|', ',') + ',' + $rost[$_] + ']' }) -join ',') + ']')
[void]$sb.Append(',"mop":{"month":"' + $asOf.ToString('yyyy-MM') + '","rows":[' + ($mopRows -join ',') + ']}')
[void]$sb.Append(',"bql":[' + (($bqlAgg.Keys | ForEach-Object { '[' + ($_ -replace '\|', ',') + ',' + $bqlAgg[$_] + ']' }) -join ',') + ']}')
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Out), $sb.ToString(), (New-Object Text.UTF8Encoding($false)))

$totMs = 0; $totMd = 0; foreach ($v in $m.Values) { $totMs += $v[0]; $totMd += $v[1] }
$totB = 0; foreach ($v in $bqlAgg.Values) { $totB += $v }
Write-Host ("As of {0} | MS {1} | MD {2} | BQL {3} | roster months {4} | wrote {5} ({6:N0} KB)" -f $asOf.ToString('dd MMM yyyy'), $totMs, $totMd, $totB, (($months | ForEach-Object -Begin { $i = 0 } -Process { "$_<-$($rosterFrom[$i])"; $i++ }) -join ' '), $Out, ((Get-Item $Out).Length / 1KB))
