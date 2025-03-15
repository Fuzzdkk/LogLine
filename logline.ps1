<#
.SYNOPSIS
    LogLine - A comprehensive log aggregation and timeline tool for blue-team SOCs.
.DESCRIPTION
    This script collects log events from files and/or Windows Event Logs, applies optional filters
    (keywords, level, source, user, computer, date/time, noise) and outputs a chronologically sorted timeline.
    
    The TL;DR summary at the top aggregates events by EventID (using event mappings loaded from events.txt)
    so that for each unique EventID (mapped and unmapped separately) it shows the earliest and latest occurrence
    along with a total count. This provides a compact overview for a SOC analyst.
    
.PARAMETERS
    -F [string[]]       : (Optional) Paths to log files.
    -E                  : (Switch) Include Windows Event Logs.
    -O [string]         : (Optional) Output file path (default: .\Timeline.txt).
    -K [string[]]       : (Optional) Keyword filter.
    -L [string[]]       : (Optional) Filter by event level.
    -S [string[]]       : (Optional) Filter by event source.
    -U [string[]]       : (Optional) Filter by user.
    -C [string[]]       : (Optional) Filter by computer.
    -D [int]            : (Optional) Number of days back to collect logs (default: 1).
    -Start [datetime]   : (Optional) Override start time.
    -End [datetime]     : (Optional) Override end time.
    -N                  : (Switch) Enable noise filtering.
    
.EXAMPLE
    # Collect Windows Event Logs from the past 3 days with noise filtering enabled:
    .\LogLine.ps1 -E -O "C:\Reports\Timeline.txt" -D 3 -N
#>

[CmdletBinding()]
param(
    [Alias("F")][string[]]$Files,
    [Alias("E")][switch]$EventLogs,
    [Alias("O")][string]$OutputFile = ".\Timeline.txt",
    [Alias("K")][string[]]$Keywords,
    [Alias("L")][string[]]$Level,
    [Alias("S")][string[]]$SourceFilter,
    [Alias("U")][string[]]$User,
    [Alias("C")][string[]]$Computer,
    [Alias("D")][int]$Days = 1,
    [Alias("Start")][datetime]$StartTime,
    [Alias("End")][datetime]$EndTime,
    [Alias("N")][switch]$ExcludeNoise
)

# Determine the script directory and load events.txt mapping file.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$eventsFilePath = Join-Path $scriptDir "events.txt"

$eventDescriptions = @{}
if (Test-Path $eventsFilePath) {
    Get-Content $eventsFilePath | ForEach-Object {
        if ($_ -match "\S") {
            $parts = $_ -split ","
            if ($parts.Length -ge 2) {
                $id = $parts[0].Trim()
                $desc = $parts[1].Trim()
                $eventDescriptions[$id] = $desc
            }
        }
    }
}

if (-not $StartTime) { $StartTime = (Get-Date).AddDays(-$Days) }
if (-not $EndTime) { $EndTime = Get-Date }

$TimestampRegexes = @(
    '^(?<timestamp>\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z)?)',
    '^(?<timestamp>\d{2}/\d{2}/\d{4}[ T]\d{2}:\d{2}:\d{2})'
)

$noisePatterns = @(
    'Secure Boot update failed',
    'NtpClient was unable to set a manual peer',
    'Windows Error Reporting: EventID 1001',
    'Fault bucket'
)

function Parse-LogLine {
    param (
        [string]$Line,
        [string[]]$Regexes
    )
    foreach ($regex in $Regexes) {
        if ($Line -match $regex) {
            $tsStr = $matches['timestamp']
            try {
                $ts = [datetime]::Parse($tsStr)
                return [PSCustomObject]@{
                    Timestamp = $ts
                    Line      = $Line.Trim()
                }
            } catch {
                continue
            }
        }
    }
    return [PSCustomObject]@{
        Timestamp = $null
        Line      = $Line.Trim()
    }
}

function Extract-EventID {
    param ([string]$Line)
    if ($Line -match "EventID\s+(\d+)") { return $matches[1] }
    else { return "N/A" }
}

# New function that returns the event summary based on events.txt mapping.
function Get-EventSummary {
    param ([psobject]$Event)
    $id = Extract-EventID -Line $Event.Line
    if ($id -ne "N/A" -and $eventDescriptions.ContainsKey($id)) {
        return "EventID $id ($($eventDescriptions[$id]))"
    }
    else {
        return "EventID $id"
    }
}

$events = @()

# Process file logs.
if ($Files) {
    foreach ($file in $Files) {
        if (Test-Path $file) {
            try {
                Write-Verbose "Processing file: $file"
                $lines = Get-Content -Path $file -ErrorAction Stop
                foreach ($line in $lines) {
                    if ($line.Trim() -ne "") {
                        $event = Parse-LogLine -Line $line -Regexes $TimestampRegexes
                        $event | Add-Member -MemberType NoteProperty -Name "Source" -Value $file
                        $events += $event
                    }
                }
            } catch {
                Write-Warning "Error reading file '$file': $_"
            }
        }
        else {
            Write-Warning "File '$file' not found."
        }
    }
}

# Process Windows Event Logs.
if ($EventLogs) {
    $elogNames = @("Application", "System", "Security")
    foreach ($elog in $elogNames) {
        try {
            Write-Verbose "Collecting events from Event Log: $elog"
            $winEvents = Get-WinEvent -LogName $elog -ErrorAction Stop
            foreach ($we in $winEvents) {
                $eventObj = [PSCustomObject]@{
                    Timestamp = $we.TimeCreated
                    Line      = "$($we.ProviderName): EventID $($we.Id) - $($we.Message)"
                    Source    = "EventLog: $elog"
                }
                $events += $eventObj
            }
        } catch {
            Write-Warning "Failed to collect events from '$elog': $_"
        }
    }
}

# Apply keyword filter.
if ($Keywords) {
    $events = $events | Where-Object {
        $include = $false
        foreach ($keyword in $Keywords) {
            if ($_.Line -match [regex]::Escape($keyword)) { $include = $true; break }
        }
        $include
    }
}

# Apply level filter.
if ($Level) {
    $events = $events | Where-Object {
        $match = $false
        foreach ($lvl in $Level) {
            if ($_.Line -match [regex]::Escape($lvl)) { $match = $true; break }
        }
        $match
    }
}

# Apply source filter.
if ($SourceFilter) {
    $events = $events | Where-Object {
        $match = $false
        foreach ($src in $SourceFilter) {
            if ($_.Source -match [regex]::Escape($src)) { $match = $true; break }
        }
        $match
    }
}

# Apply user filter.
if ($User) {
    $events = $events | Where-Object {
        $match = $false
        foreach ($usr in $User) {
            if ($_.Line -match [regex]::Escape($usr)) { $match = $true; break }
        }
        $match
    }
}

# Apply computer filter.
if ($Computer) {
    $events = $events | Where-Object {
        $match = $false
        foreach ($comp in $Computer) {
            if ($_.Line -match [regex]::Escape($comp)) { $match = $true; break }
        }
        $match
    }
}

# Filter by date range.
$events = $events | Where-Object {
    if ($_.Timestamp) { ($_.Timestamp -ge $StartTime) -and ($_.Timestamp -le $EndTime) }
    else { $true }
}

# Exclude noise events if requested.
if ($ExcludeNoise) {
    $events = $events | Where-Object {
        $isNoise = $false
        foreach ($pattern in $noisePatterns) {
            if ($_.Line -match $pattern) { $isNoise = $true; break }
        }
        -not $isNoise
    }
}

$eventsWithTS = $events | Where-Object { $_.Timestamp -ne $null } | Sort-Object -Property Timestamp
$eventsWithoutTS = $events | Where-Object { $_.Timestamp -eq $null }

# --- Build Header ---
$header = @()
$header += "=========================================="
$header += "         LogLine Timeline Report          "
$header += "=========================================="
$header += "Generated on   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$header += "Collection Date: $(Get-Date -Format 'dd/MM/yyyy')"
if ($Files) { $header += "Input Files    : $($Files -join ', ')" }
if ($EventLogs) { $header += "Included Logs  : Application, System, Security" }
if ($Keywords) { $header += "Keyword Filter : $($Keywords -join ', ')" }
if ($Level) { $header += "Level Filter   : $($Level -join ', ')" }
if ($SourceFilter) { $header += "Source Filter  : $($SourceFilter -join ', ')" }
if ($User) { $header += "User Filter    : $($User -join ', ')" }
if ($Computer) { $header += "Computer Filter: $($Computer -join ', ')" }
$header += "Timeframe      : $($StartTime.ToString('yyyy-MM-dd HH:mm:ss')) to $($EndTime.ToString('yyyy-MM-dd HH:mm:ss'))"
if ($ExcludeNoise) { $header += "Noise Filter   : Enabled" }
$header += "Total Events   : $($events.Count)"
$header += "=========================================="
$header += ""

# --- Build TL;DR Summary Block ---
$tlSummary = @()
$tlSummary += "TL;DR Summary:"
$tlSummary += "--------------"
$tlSummary += "Total events processed  : $($events.Count)"
$tlSummary += "Events with timestamp   : $($eventsWithTS.Count)"
if ($eventsWithTS.Count -gt 0) {
    $minDate = ($eventsWithTS | Measure-Object -Property Timestamp -Minimum).Minimum
    $maxDate = ($eventsWithTS | Measure-Object -Property Timestamp -Maximum).Maximum
    $tlSummary += "Date range              : $($minDate.ToString('yyyy-MM-dd')) to $($maxDate.ToString('yyyy-MM-dd'))"
}

# Aggregate mapped events by EventID.
$mappedEvents = $eventsWithTS | Where-Object {
    $id = Extract-EventID -Line $_.Line
    ($id -ne "N/A") -and $eventDescriptions.ContainsKey($id)
}
$mappedGrouped = $mappedEvents | Group-Object { Extract-EventID -Line $_.Line }
$mappedSummaryLines = @()
foreach ($grp in $mappedGrouped) {
    $id = $grp.Name
    $desc = $eventDescriptions[$id]
    $first = ($grp.Group | Measure-Object -Property Timestamp -Minimum).Minimum.ToString("yyyy-MM-dd HH:mm:ss")
    $last = ($grp.Group | Measure-Object -Property Timestamp -Maximum).Maximum.ToString("yyyy-MM-dd HH:mm:ss")
    $count = $grp.Count
    $mappedSummaryLines += "  [$first -> $last] EventID $id ($desc) : $count events"
}

# Aggregate unmapped events.
$unmappedEvents = $eventsWithTS | Where-Object {
    $id = Extract-EventID -Line $_.Line
    ($id -eq "N/A") -or (-not $eventDescriptions.ContainsKey($id))
}
$unmappedGrouped = $unmappedEvents | Group-Object { Extract-EventID -Line $_.Line }
$unmappedSummaryLines = @()
foreach ($grp in $unmappedGrouped) {
    $id = $grp.Name
    $first = ($grp.Group | Measure-Object -Property Timestamp -Minimum).Minimum.ToString("yyyy-MM-dd HH:mm:ss")
    $last = ($grp.Group | Measure-Object -Property Timestamp -Maximum).Maximum.ToString("yyyy-MM-dd HH:mm:ss")
    $count = $grp.Count
    $unmappedSummaryLines += "  [$first -> $last] EventID $id : $count events"
}

$tlSummary += "Event Descriptions Fired (Mapped):"
$tlSummary += $mappedSummaryLines
if ($unmappedSummaryLines.Count -gt 0) {
    $tlSummary += "Unmapped Event IDs:"
    $tlSummary += $unmappedSummaryLines
}
$tlSummary += "--------------"
$tlSummary += ""

# --- Build Detailed Timeline by Day ---
$groupedByDay = $eventsWithTS | Group-Object { $_.Timestamp.ToString("yyyy-MM-dd") } | Sort-Object Name
$timelineDetail = @()
foreach ($grp in $groupedByDay) {
    $dateHeader = "== Date: $($grp.Name) =="
    $timelineDetail += $dateHeader
    $timelineDetail += ("-" * $dateHeader.Length)
    foreach ($event in $grp.Group | Sort-Object Timestamp) {
        $time = $event.Timestamp.ToString("HH:mm:ss")
        $timelineDetail += "[$time]  $($event.Line)  (Source: $($event.Source))"
    }
    $timelineDetail += ""
}

$noTSSection = @()
if ($eventsWithoutTS.Count -gt 0) {
    $noTSSection += "== Events with No Timestamp =="
    $noTSSection += "--------------------------------"
    foreach ($event in $eventsWithoutTS) {
        $noTSSection += "[UNKNOWN]  $($event.Line)  (Source: $($event.Source))"
    }
    $noTSSection += ""
}

$reportContent = $header + $tlSummary + $timelineDetail + $noTSSection

# Ensure output directory exists.
$outputDir = Split-Path -Parent $OutputFile
if (-not (Test-Path $outputDir)) {
    try {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        Write-Verbose "Created output directory: $outputDir"
    } catch {
        Write-Error "Failed to create output directory '$outputDir': $_"
        exit 1
    }
}

try {
    $reportContent | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
    Write-Output "Timeline report generated: $OutputFile"
} catch {
    Write-Error "Failed to write output file: $_"
}
