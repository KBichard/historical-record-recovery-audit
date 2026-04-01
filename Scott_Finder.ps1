# ============================================
# Historical_Document_Finder.ps1
# Missing instrument validation against archived ZIP files
# Recursively scans archive folders and copies matched files
# ============================================

param(
    [string]$ArchiveRoot = "\\path\to\archive\History",
    [string]$WorkingRoot = "C:\Portfolio\HistoricalRecovery",
    [string]$InputWorkbook = "Missing_Instruments.xlsx",
    [string]$WorksheetName = "Sheet1",
    [int]$InstrumentColumn = 3
)

$ExcelPath = Join-Path $WorkingRoot $InputWorkbook
$OutputCsv = Join-Path $WorkingRoot "Missing_Instrument_Existence.csv"
$OutputDir = Join-Path $WorkingRoot "RecoveredFiles"

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

Write-Host "Opening Excel (COM mode)..."

$Excel = New-Object -ComObject Excel.Application
$Excel.Visible = $false
$Excel.DisplayAlerts = $false

$Workbook = $Excel.Workbooks.Open($ExcelPath)
$Sheet = if ($WorksheetName) { $Workbook.Worksheets.Item($WorksheetName) } else { $Workbook.Worksheets.Item(1) }

$Row = 2
$Missing = @()

while ($Sheet.Cells.Item($Row, $InstrumentColumn).Text -ne "") {
    $Val = $Sheet.Cells.Item($Row, $InstrumentColumn).Text.Trim()
    if ($Val -match '^\d+$') {
        $Missing += $Val
    }
    $Row++
}

$Workbook.Close($false)
$Excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($Excel) | Out-Null

$Missing = $Missing | Sort-Object -Unique
Write-Host "Loaded $($Missing.Count) missing instrument numbers."

Add-Type -AssemblyName System.IO.Compression.FileSystem

$Index = @{}
Write-Host "Scanning ZIP files recursively..."

Get-ChildItem -Path $ArchiveRoot -Filter "*.zip" -Recurse | ForEach-Object {
    try {
        $ZipPath = $_.FullName
        $Archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)

        foreach ($Entry in $Archive.Entries) {
            if ($Entry.Name -match '^(\d+)_.*\.(pdf|tif)$') {
                $Inst = $Matches[1]

                if ($Missing -contains $Inst -and -not $Index.ContainsKey($Inst)) {
                    $DestPath = Join-Path $OutputDir $Entry.Name

                    if (-not (Test-Path $DestPath)) {
                        $EntryStream = $Entry.Open()
                        $FileStream  = [System.IO.File]::Create($DestPath)
                        $EntryStream.CopyTo($FileStream)
                        $FileStream.Close()
                        $EntryStream.Close()
                    }

                    $Index[$Inst] = [PSCustomObject]@{
                        Folder = $_.Directory.Name
                        Zip    = $_.Name
                        File   = $Entry.Name
                    }
                }
            }
        }

        $Archive.Dispose()
    }
    catch {
        Write-Warning "Unreadable ZIP: $($_.FullName)"
    }
}

Write-Host "ZIP scan complete."

$Results = foreach ($Inst in $Missing) {
    if ($Index.ContainsKey($Inst)) {
        [PSCustomObject]@{
            InstrumentNumber = $Inst
            Status           = "FOUND"
            Folder           = $Index[$Inst].Folder
            ZipFile          = $Index[$Inst].Zip
            FileName         = $Index[$Inst].File
            OutputLocation   = (Join-Path $OutputDir $Index[$Inst].File)
        }
    }
    else {
        [PSCustomObject]@{
            InstrumentNumber = $Inst
            Status           = "NOT FOUND"
            Folder           = ""
            ZipFile          = ""
            FileName         = ""
            OutputLocation   = ""
        }
    }
}

$Results | Export-Csv $OutputCsv -NoTypeInformation

Write-Host "Complete"
Write-Host "Results CSV:"
Write-Host $OutputCsv
Write-Host "Recovered files location:"
Write-Host $OutputDir
