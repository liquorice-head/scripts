$today = Get-Date -Format "yyyy_MM_dd"
$filePath = "path to log file" + $today + "*.log"

$file = Get-ChildItem $filePath -ErrorAction SilentlyContinue

$status = "No Status Found"

if ($file) {
    Get-Content $file.FullName | ForEach-Object {
        if ($_ -match "FirstStatus") {
            $status = "FirstStatus"
        } elseif ($_ -match "SecondStatus") {
            $status = "SecondStatus"
        }
    }
} else {
    $status = "File Not Found"
}

Write-Host "Status: $status"
