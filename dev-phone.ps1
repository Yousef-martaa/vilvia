# Vilvia Developer Convenience Script for Physical Android Devices
#
# This script starts the FastAPI backend, configures ADB reverse port forwarding,
# and launches the Flutter app on a connected Android phone.
#
# Requirements:
# 1. A physical Android device with USB debugging enabled.
# 2. A valid .env file at the repository root.
# 3. Python and Flutter environments configured (see README.md).

$envFile = Join-Path $PSScriptRoot ".env"
if (-not (Test-Path $envFile)) {
    Write-Host "Error: .env file not found at $envFile" -ForegroundColor Red
    Write-Host "Copy .env.example to .env and fill in your Supabase credentials."
    exit 1
}

# Parse .env for Supabase credentials (required for Flutter run)
$supabaseUrl = ""
$supabaseKey = ""
Get-Content $envFile | ForEach-Object {
    if ($_ -match "^SUPABASE_URL=(.*)") { $supabaseUrl = $matches[1].Trim().Trim("'").Trim('"') }
    if ($_ -match "^SUPABASE_PUBLISHABLE_KEY=(.*)") { $supabaseKey = $matches[1].Trim().Trim("'").Trim('"') }
}

if ([string]::IsNullOrWhiteSpace($supabaseUrl) -or [string]::IsNullOrWhiteSpace($supabaseKey)) {
    Write-Host "Error: SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must be set in .env" -ForegroundColor Red
    exit 1
}

# Export to environment for backend process inheritance
$env:SUPABASE_URL = $supabaseUrl
$env:SUPABASE_PUBLISHABLE_KEY = $supabaseKey

# 1. Locate and verify ADB
$adbPath = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adbPath)) {
    Write-Host "Error: ADB not found at $adbPath" -ForegroundColor Red
    Write-Host "Please ensure the Android SDK is installed and ADB is available."
    exit 1
}

# 2. Verify connected device
$devices = & $adbPath devices | Select-String "\tdevice$"
if (-not $devices) {
    Write-Host "Error: No authorized Android devices found via ADB." -ForegroundColor Red
    Write-Host "Check that your phone is connected, USB debugging is enabled, and you have authorized the connection."
    exit 1
}

Write-Host "Configuring ADB reverse port forwarding (8000 -> 8000)..."
& $adbPath reverse tcp:8000 tcp:8000

# 3. Start Backend
Write-Host "Starting backend in a separate terminal..."
$backendDir = Join-Path $PSScriptRoot "backend"
# We start powershell -NoExit so the developer can see backend logs if it fails or runs.
Start-Process powershell -WorkingDirectory $backendDir -ArgumentList "-NoExit", "-Command", "python -m uvicorn app.main:app --reload --port 8000"

# 4. Wait for Backend
Write-Host "Waiting for backend to be ready at http://127.0.0.1:8000/health" -NoNewline
$maxRetries = 15
$retryCount = 0
$started = $false
while ($retryCount -lt $maxRetries) {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -Method Get -TimeoutSec 1 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $started = $true
            break
        }
    } catch {
        # Backend not ready yet
    }
    Start-Sleep -Seconds 2
    $retryCount++
    Write-Host "." -NoNewline
}

if (-not $started) {
    Write-Host "`nError: Backend failed to respond at http://127.0.0.1:8000/health after several attempts." -ForegroundColor Red
    Write-Host "Check the backend terminal for error messages."
    exit 1
}

Write-Host "`nBackend is ready. Launching Flutter..."
# 5. Launch Flutter
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000 `
            --dart-define=SUPABASE_URL="$supabaseUrl" `
            --dart-define=SUPABASE_PUBLISHABLE_KEY="$supabaseKey"
