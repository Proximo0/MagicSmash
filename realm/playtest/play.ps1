# Horde & Hearth playtest launcher (realm/playtest, shipped in the realm-playtest-windows CI artifact).
# Reads the LAN host's info that the station job lanhost publishes (lan/host.txt on branch station-results: ip, port,
# state, its certificate), waits until a server is live with at least 10 minutes left, saves the certificate and
# starts the game pointed at that server, trusting exactly that certificate (debug build: --dev-cert).
param([switch]$DryRun)   # -DryRun: find the server and print the command, start nothing
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$url = 'https://raw.githubusercontent.com/Proximo0/MagicSmash/station-results/lan/host.txt'
$exe = Join-Path $here 'HordeAndHearth.exe'
if (-not $DryRun -and -not (Test-Path $exe)) { Write-Host "HordeAndHearth.exe is not next to this script: unzip the whole folder first."; exit 1 }
$f = $null; $text = ''
for ($i = 1; $i -le 40; $i++) {
    try { $text = (Invoke-WebRequest -UseBasicParsing -Uri "$url`?nocache=$(Get-Random)").Content } catch { $text = '' }
    $f = @{}
    foreach ($l in ($text -split "`n")) { if ($l -match '^([a-z_]+)=(.*)$') { $f[$Matches[1]] = $Matches[2].Trim() } }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $live = $f['state'] -eq 'live' -and $f['end_epoch'] -and $f['updated_epoch'] -and
        ([int64]$f['end_epoch'] -gt $now + 600) -and ([int64]$f['updated_epoch'] -gt $now - 900)
    if ($live) { break }
    $f = $null
    Write-Host "Waiting for the game server on the Linux PC to come up (check $i of 40, every 30 s)..."
    Start-Sleep -Seconds 30
}
if ($null -eq $f) { Write-Host 'No live server found in 20 minutes. Is the Linux PC on and running its station?'; exit 1 }
$m = [regex]::Match($text, '-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----')
if (-not $m.Success) { Write-Host 'The server info has no certificate.'; exit 1 }
$pem = Join-Path $env:TEMP 'horde_and_hearth_lan.pem'
Set-Content -Path $pem -Value $m.Value -Encoding ascii
$left = [int](([int64]$f['end_epoch'] - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) / 60)
Write-Host "Server found on $($f['machine']) at $($f['ip']):$($f['tcp_port']), $left minutes left in this session. Starting the game."
$gameArgs = @('--', "--gateway=$($f['ip']):$($f['tcp_port'])", "--dev-cert=$pem")
if ($DryRun) { Write-Host "DRYRUN $exe $($gameArgs -join ' ')"; exit 0 }
Start-Process -FilePath $exe -WorkingDirectory $here -ArgumentList $gameArgs
