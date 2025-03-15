# LogLine Timeline Report Tool

LogLine is a WIP log aggregation and timeline summarization tool. It collects log events from local files and Windows Event Logs, applies flexible filtering (by keywords, event level, source, user, computer, and date range), and uses an external event mapping file to correlate EventIDs with descriptive text. The tool then generates a concise TL;DR summary along with a detailed, day-by-day timeline report.

## Features

- **Log Collection:**  
  - Reads log events from specified local text files.
  - Optionally collects events from Windows Event Logs (Application, System, and Security).

- **Flexible Filtering:**  
  - Filter by keywords, event level, source, user, computer, and date range.
  - Option to exclude noise events based on configurable patterns.

- **EventID Mapping:**  
  - Uses an external `events.txt` file (in the same directory as the script) to map EventIDs to descriptions.
  - Easily extendable by adding new mappings to `events.txt`.

- **Summarized TL;DR Report:**  
  - Aggregates events by EventID and provides the first and last occurrence timestamps along with a total count.
  - Displays mapped and unmapped events separately for easy review.

- **Detailed Timeline:**  
  - Produces a chronological, day-by-day breakdown of all events for further drill-down analysis.

- **Output Options:**  
  - Generates the timeline report as a text file (default: `.\Timeline.txt`), making it easy to share and archive.

## Requirements

- **PowerShell 5.1 or later** (typically available on Windows 10/11).
- An `events.txt` file located in the same directory as `LogLine.ps1` with EventID mappings formatted as follows:

1100,The event logging service has shut down<br>
4798,A user's local group membership was enumerated.<br>
1102,The audit log was cleared

## Microsoft Recommended Event IDs

The provided `events.txt` file includes a list of EventIDs that Microsoft recommends should be logged as a minimum for effective security auditing and monitoring. This list is based on the events detailed in Microsoft's documentation. For more details on the recommended events, please refer to the [Appendix L – Events to Monitor](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/appendix-l--events-to-monitor) page.


## Installation

1. Clone or download this repository.
2. Place `LogLine.ps1` and `events.txt` in the same working directory.
3. (Optional) Edit `events.txt` to update or add additional EventID mappings as needed.

## Usage

Run the script as administrator using PowerShell with the desired parameters. The key parameters are:

- `-F [string[]]`: (Optional) Paths to log files to process.
- `-E`: Include Windows Event Logs.
- `-O [string]`: (Optional) Output file path. Default is `.\Timeline.txt`.
- `-K [string[]]`: (Optional) Keyword filter.
- `-L [string[]]`: (Optional) Filter by event level.
- `-S [string[]]`: (Optional) Filter by event source.
- `-U [string[]]`: (Optional) Filter by user.
- `-C [string[]]`: (Optional) Filter by computer.
- `-D [int]`: (Optional) Number of days back to collect logs (default is 1).
- `-Start [datetime]`: (Optional) Override the start time.
- `-End [datetime]`: (Optional) Override the end time.
- `-N`: (Switch) Enable noise filtering.

### Example Commands

- **Collect Windows Event Logs from the past 3 days with noise filtering enabled:**
```powershell
.\LogLine.ps1 -E -O "C:\Reports\Timeline.txt" -D 3 -N
Process a specific log file with a keyword filter:

.\LogLine.ps1 -F "C:\Logs\mylog.txt" -K error -O "C:\Reports\Timeline.txt"
Output
The timeline report includes:

Header:
Metadata such as generation time, collection date, filters applied, and the overall timeframe.

TL;DR Summary:
A compact overview that aggregates events by EventID (both mapped and unmapped). For each unique EventID, it shows:

The first and last occurrence timestamps.
The total count of events.
This summary is arranged chronologically.

Detailed Timeline:
A breakdown of events grouped by day, with each event’s time, description, and source.

Events Without Timestamps:
A separate section for any events that could not be timestamped.
```
### Contributing
Contributions, suggestions, and bug reports are welcome!
Feel free to fork this repository, make your changes, and submit a pull request.

### License
This project is licensed under the MIT License.
