<#
  TRACE reconciliation checks R1-R9 (tracking pipeline) and C1-C2 (communication follow-up).
  Requires: PnP.PowerShell 2.x and an Entra app registration for -ClientId.
  UNTESTED against the tenant. Internal field names are inferred from the flow JSON;
  confirm them against the list schemas before trusting a FAIL.

  Usage:
    ./TRACE_Reconciliation.ps1 -SiteUrl https://<tenant>.sharepoint.com/sites/<site> -ClientId <guid> -RunId 'TRACE-...'
    ./TRACE_Reconciliation.ps1 ... -RunId 'TRACE-...' -SkipCommunication
#>
param(
  [Parameter(Mandatory)] [string] $SiteUrl,
  [Parameter(Mandatory)] [string] $ClientId,
  [Parameter(Mandatory)] [string] $RunId,
  [int] $LeaseMinutes = 30,
  [switch] $SkipCommunication
)

# ---- FILL IN BEFORE FIRST RUN -------------------------------------------------------------
# This public copy has the list GUIDs replaced by placeholders. Replace each '<LIST_...>' value
# with the real GUID (no braces). To find one: open the list -> gear -> List settings -> the
# browser URL ends in List=%7B<GUID>%7D. reference/list-map.md says which list each placeholder is.
# A list display name also works here (e.g. 'Trace_Workflow') because Get-PnPListItem accepts either.
$L = @{
  Chunks      = '<LIST_CHUNKS>'
  Results     = '<LIST_RESULTS>'
  ImportRuns  = '<LIST_IMPORT_RUNS>'
  Counter     = '<LIST_CASE_COUNTER>'
  ActiveTrace = '<LIST_TRACE_WORKFLOW>'
  HistTrace   = '<LIST_HISTORICAL>'
  BatchItems  = '<LIST_BATCH_ITEMS>'
}

$unset = $L.GetEnumerator() | Where-Object { $_.Value -like '<*>' }
if ($unset) { throw "Fill in the list GUIDs at the top of the script first: $(($unset.Name) -join ', ')" }

Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $ClientId

$script:Fails = 0
function Report([string]$Id, [bool]$Pass, [string]$Detail) {
  $tag = if ($Pass) { 'PASS' } else { $script:Fails++; 'FAIL' }
  Write-Host ("[{0}] {1}  {2}" -f $tag, $Id, $Detail)
}
function V($item, $name) {           # FieldValues accessor that flattens choice/lookup objects
  $v = $item.FieldValues[$name]
  if ($null -ne $v -and $v.PSObject.Properties['LookupValue']) { return $v.LookupValue }
  return $v
}
function Get-ByText($list, $field, $value, [string[]]$fields) {
  $esc = [System.Security.SecurityElement]::Escape($value)
  $caml = "<View Scope='RecursiveAll'><Query><Where><Eq><FieldRef Name='$field'/><Value Type='Text'>$esc</Value></Eq></Where></Query><RowLimit Paged='TRUE'>2000</RowLimit></View>"
  Get-PnPListItem -List $list -Query $caml -PageSize 2000 -Fields $fields
}

# ---------- Load run data ----------
$chunks  = @(Get-ByText $L.Chunks  'field_1' $RunId @('ID','field_3','field_5','field_6','field_7','field_8','field_9','TotalChunkCount','ClaimedDate'))
$results = @(Get-ByText $L.Results 'field_1' $RunId @('ID','Title','field_3','field_4','field_5','field_9','ChunkNumber','CaseReviewDecision','CaseCreationEligible'))
$run     = @(Get-ByText $L.ImportRuns 'RunID' $RunId @('ID','FinalizationStatus','RunStatus','Modified','FinalizationStartedDate'))
Write-Host "RunID $RunId : $($chunks.Count) chunk(s), $($results.Count) result(s), $($run.Count) import-run row(s)"

# R1 one result per tracking number
$dupTitle = $results | Group-Object { V $_ 'Title' }   | Where-Object Count -gt 1
$dupTrk   = $results | Group-Object { ("" + (V $_ 'field_3')).Trim().ToUpper() } | Where-Object Count -gt 1
Report 'R1' (($dupTitle.Count + $dupTrk.Count) -eq 0) "duplicate keys: $($dupTitle.Count); duplicate tracking numbers: $($dupTrk.Count) $(($dupTrk | Select-Object -First 5 -Expand Name) -join ',')"

# R2 chunks complete and balanced
$total = if ($chunks.Count) { [int](V $chunks[0] 'TotalChunkCount') } else { 0 }
$notDone = $chunks | Where-Object { (V $_ 'field_8') -ne 'Completed' }
$unbal   = $chunks | Where-Object { [int](V $_ 'field_6') -ne [int](V $_ 'field_5') -or [int](V $_ 'field_7') -ne 0 }
Report 'R2' ($chunks.Count -gt 0 -and $chunks.Count -eq $total -and $notDone.Count -eq 0 -and $unbal.Count -eq 0) `
  "chunks $($chunks.Count)/$total; not Completed: $($notDone.Count) [$((($notDone | ForEach-Object { "#$(V $_ 'field_3')=$(V $_ 'field_8')" }) -join ' '))]; count-unbalanced: $($unbal.Count)"

# R3 per-chunk results = distinct tracking numbers in payload
$byChunk = $results | Group-Object { [int](V $_ 'ChunkNumber') } -AsHashTable
$r3Bad = @(); $payloadMax = 0
foreach ($c in $chunks) {
  $n = [int](V $c 'field_3'); $raw = "" + (V $c 'field_9'); $payloadMax = [Math]::Max($payloadMax, $raw.Length)
  try { $distinct = @(($raw | ConvertFrom-Json) | ForEach-Object { ("" + $_.TrackingNumber).Trim().ToUpper() } | Sort-Object -Unique).Count }
  catch { $r3Bad += "#${n}: payload JSON invalid"; continue }
  $have = if ($byChunk -and $byChunk.ContainsKey($n)) { $byChunk[$n].Count } else { 0 }
  if ($have -ne $distinct) { $r3Bad += "#${n}: results $have vs distinct $distinct" }
}
Report 'R3' ($r3Bad.Count -eq 0) "$($r3Bad -join '; ')  (max payload length $payloadMax chars)"

# R4 totals agree
$sumExpected = ($chunks | ForEach-Object { [int](V $_ 'field_5') } | Measure-Object -Sum).Sum
$distinctRun = @($results | ForEach-Object { ("" + (V $_ 'field_3')).Trim().ToUpper() } | Sort-Object -Unique).Count
Report 'R4' ($sumExpected -eq $results.Count -and $results.Count -eq $distinctRun) "sum ExpectedCount $sumExpected; results $($results.Count); distinct tracking $distinctRun"

# R5 outcome distribution
$known = 'Active Updated','Historical Match','New Case Required','New Case Created','Dashboard Only - No Case',
         'Reference History - No Action','Operational Dashboard - No Action','Communication Review',
         'Manual Classification','Needs Case Review','Follow-Up Required','Carrier Follow-Up Required'
$dist = $results | Group-Object { V $_ 'field_4' }
$unknown = $dist | Where-Object { $known -notcontains $_.Name }
$status = if ($run.Count) { V $run[0] 'FinalizationStatus' } else { '' }
$ncr = ($dist | Where-Object Name -eq 'New Case Required').Count
Write-Host ("     outcomes: " + (($dist | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' | '))
Report 'R5' ($unknown.Count -eq 0 -and -not ($status -eq 'Completed' -and $ncr -gt 0)) "unknown outcomes: $(($unknown.Name) -join ','); New Case Required remaining while Completed: $(if($status -eq 'Completed'){$ncr}else{'n/a'})"

# R6 created cases resolve
$created = $results | Where-Object { (V $_ 'field_4') -eq 'New Case Created' }
$r6Bad = @()
foreach ($r in $created) {
  $tid = V $r 'field_5'; $cn = V $r 'field_9'
  if (-not $tid -or -not $cn) { $r6Bad += "result $(V $r 'ID') missing trace id/case number"; continue }
  $t = Get-PnPListItem -List $L.ActiveTrace -Id ([int]$tid) -Fields 'CaseNumber','TrackingNumber' -ErrorAction SilentlyContinue
  if (-not $t) { $r6Bad += "result $(V $r 'ID') -> trace $tid not found"; continue }
  if ((V $t 'CaseNumber') -ne $cn -or ("" + (V $t 'TrackingNumber')).ToUpper() -ne ("" + (V $r 'field_3')).ToUpper()) { $r6Bad += "result $(V $r 'ID') case/tracking mismatch" }
}
Report 'R6' ($r6Bad.Count -eq 0) "created $($created.Count); problems: $($r6Bad.Count) $(($r6Bad | Select-Object -First 5) -join '; ')"

# R7 case numbers unique (active + historical) and within counter
$cases = @(Get-PnPListItem -List $L.ActiveTrace -PageSize 2000 -Fields 'CaseNumber') + @(Get-PnPListItem -List $L.HistTrace -PageSize 2000 -Fields 'CaseNumber')
$cnDup = $cases | Where-Object { V $_ 'CaseNumber' } | Group-Object { V $_ 'CaseNumber' } | Where-Object Count -gt 1
$counter = Get-PnPListItem -List $L.Counter -PageSize 2000 -Fields 'Title','LastSequence'
$over = @()
foreach ($day in ($cases | Where-Object { "$(V $_ 'CaseNumber')" -match '^\d{11,}$' } | Group-Object { "$(V $_ 'CaseNumber')".Substring(0,8) })) {
  $maxSeq = ($day.Group | ForEach-Object { [int]"$(V $_ 'CaseNumber')".Substring(8) } | Measure-Object -Maximum).Maximum
  $c = $counter | Where-Object { (V $_ 'Title') -eq $day.Name } | Select-Object -First 1
  if ($c -and $maxSeq -gt [int](V $c 'LastSequence')) { $over += "$($day.Name): max $maxSeq > counter $(V $c 'LastSequence')" }
}
Report 'R7' ($cnDup.Count -eq 0 -and $over.Count -eq 0) "duplicate case numbers: $($cnDup.Count) $(($cnDup.Name | Select-Object -First 5) -join ','); counter behind: $($over -join '; ')"

# R8 import run not stuck
$now = Get-Date
$r8 = $true; $r8d = "status '$status'"
if ($run.Count -and $status -eq 'Processing' -and ($now - [datetime](V $run[0] 'Modified')).TotalMinutes -gt 30) { $r8 = $false; $r8d += " for > 30 min" }
if ($status -eq 'Completed' -and $script:Fails -gt 0) { $r8 = $false; $r8d += " but earlier checks failed" }
Report 'R8' $r8 $r8d

# R9 orphaned chunks (all runs)
$orphan = @(Get-ByText $L.Chunks 'field_8' 'Processing' @('ID','field_1','field_3','ClaimedDate')) |
  Where-Object { $d = V $_ 'ClaimedDate'; -not $d -or ($now.ToUniversalTime() - ([datetime]$d).ToUniversalTime()).TotalMinutes -gt $LeaseMinutes }
Report 'R9' ($orphan.Count -eq 0) "chunks Processing beyond $LeaseMinutes-min lease: $($orphan.Count) $((($orphan | Select-Object -First 5 | ForEach-Object { "$(V $_ 'field_1')#$(V $_ 'field_3')" })) -join ', ')"

# ---------- Communication follow-up (after the plan's columns exist) ----------
if (-not $SkipCommunication) {
  $sent = @(Get-ByText $L.BatchItems 'field_22' 'Sent' @('ID','field_3','field_8','field_23','FollowUpRequired','FollowUpStatus','IsTestRecord'))
  $open = 'Pending','Due Soon','Due Today','Overdue'
  # C1/C2 need the template rule; here we check the item-level flags the plan writes.
  $c1 = $sent | Where-Object { (V $_ 'FollowUpRequired') -eq $true -and -not (V $_ 'FollowUpStatus') }
  $c2 = $sent | Where-Object { (V $_ 'FollowUpRequired') -ne $true -and (V $_ 'FollowUpStatus') -and (V $_ 'FollowUpStatus') -ne 'Not Required' }
  Report 'C1' ($c1.Count -eq 0) "sent + FollowUpRequired but no status: $($c1.Count)"
  Report 'C2' ($c2.Count -eq 0) "sent + not required but has follow-up status: $($c2.Count)"
  $q = $sent | Where-Object { $open -contains (V $_ 'FollowUpStatus') -and (V $_ 'IsTestRecord') -ne $true } | Group-Object { V $_ 'FollowUpStatus' }
  Write-Host ("     C3 queue counts (compare with digest and Power BI): " + (($q | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' | '))
}

Write-Host ""
if ($script:Fails -eq 0) { Write-Host "ALL CHECKS PASSED" } else { Write-Host "$script:Fails CHECK(S) FAILED" }
exit $script:Fails
