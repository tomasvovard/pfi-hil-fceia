# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(ParameterSetName = 'Run', Mandatory = $true)]
    [string]$Port,

    [Parameter(ParameterSetName = 'Run')]
    [int]$TestId,

    [Parameter(ParameterSetName = 'Run')]
    [switch]$All,

    [Parameter(ParameterSetName = 'Run')]
    [switch]$ArmPrompt,

    [Parameter(ParameterSetName = 'Run')]
    [string]$OutputDir,

    [Parameter(ParameterSetName = 'Ports', Mandatory = $true)]
    [switch]$ListPorts,

    [Parameter(ParameterSetName = 'Run')]
    [int]$Baud = 115200
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$TestOrder = @(11, 12, 2, 31, 32, 41, 42, 5)
$TestNames = @{
    11 = 'E1a'; 12 = 'E1b'; 2 = 'E2'; 31 = 'E3a'
    32 = 'E3b'; 41 = 'E4a'; 42 = 'E4b'; 5 = 'E5'
}

if ($ListPorts) {
    $names = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
    if ($names.Count -eq 0) {
        Write-Host 'No se encontraron puertos serie.'
        exit 1
    }
    $names | ForEach-Object { Write-Host $_ }
    exit 0
}

if (-not $All -and $TestId -eq 0) {
    throw 'Indique -TestId 11 (por ejemplo) o use -All.'
}
if (-not $All -and $TestOrder -notcontains $TestId) {
    throw "TEST $TestId no existe. Valores: $($TestOrder -join ', ')."
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $OutputDir = Join-Path 'captures' $stamp
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$TranscriptPath = Join-Path $OutputDir 'transcript.jsonl'
$ResultsPath = Join-Path $OutputDir 'results.csv'
if ((Test-Path -LiteralPath $TranscriptPath) -or (Test-Path -LiteralPath $ResultsPath)) {
    throw "OutputDir ya contiene una corrida: $OutputDir. Use una carpeta nueva."
}
$script:RequestId = 1

function Write-Audit {
    param([string]$Direction, [string]$Line)
    Write-Host "$Direction $Line"
    $entry = [ordered]@{
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        direction = $Direction
        line = $Line
    }
    ($entry | ConvertTo-Json -Compress) | Add-Content -LiteralPath $TranscriptPath -Encoding UTF8
}

function ConvertFrom-ProtocolFields {
    param([string]$Line)
    $fields = @{}
    foreach ($token in ($Line -split '\s+')) {
        if ($token -match '^([^=]+)=(.*)$') {
            $fields[$Matches[1]] = $Matches[2]
        }
    }
    return $fields
}

function Read-ProtocolLine {
    param([System.IO.Ports.SerialPort]$Serial, [DateTime]$Deadline)
    while ([DateTime]::UtcNow -lt $Deadline) {
        try {
            $line = $Serial.ReadLine().Trim()
            if ($line.Length -gt 0) {
                Write-Audit 'RX' $line
                return $line
            }
        }
        catch [System.TimeoutException] {
            # Poll until the absolute deadline while keeping Ctrl+C responsive.
        }
    }
    throw 'Timeout esperando una linea del firmware.'
}

function Send-ProtocolCommand {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [string]$Command,
        [double]$TimeoutSeconds = 2.0
    )
    $id = $script:RequestId
    $script:RequestId++
    $prefix = "@$id"
    $wire = "$prefix $Command"
    Write-Audit 'TX' $wire
    $Serial.WriteLine($wire)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($true) {
        $line = Read-ProtocolLine $Serial $deadline
        if ($line.StartsWith($prefix + ' ')) {
            $response = $line.Substring($prefix.Length + 1)
            if ($response.StartsWith('ERR')) {
                throw "$Command`: $response"
            }
            return $response
        }
    }
}

function Wait-ProtocolEvent {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [string]$State,
        [int]$ExpectedTest,
        [double]$TimeoutSeconds
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($true) {
        $line = Read-ProtocolLine $Serial $deadline
        if (-not $line.StartsWith('!EVT ')) { continue }
        $fields = ConvertFrom-ProtocolFields $line
        if ($fields.ContainsKey('STATE') -and $fields['STATE'] -eq $State -and
            $fields.ContainsKey('TEST') -and [int]$fields['TEST'] -eq $ExpectedTest) {
            return $fields
        }
    }
}

function Save-Result {
    param([hashtable]$Fields)
    $row = [ordered]@{}
    foreach ($name in @('RESULT','TEST','STEPS','SAMPLES','IL_MIN_RAW','IL_MAX_RAW',
            'IL_MEAN_RAW','VO_MIN_RAW','VO_MAX_RAW','VO_MEAN_RAW','IL_ZERO_RAW',
            'VO_ZERO_RAW','ADC_OVF','ISR_MAX_TICKS','FLAGS')) {
        $row[$name] = if ($Fields.ContainsKey($name)) { $Fields[$name] } else { '' }
    }
    $object = [PSCustomObject]$row
    if (Test-Path -LiteralPath $ResultsPath) {
        $object | Export-Csv -LiteralPath $ResultsPath -NoTypeInformation -Append -Encoding UTF8
    }
    else {
        $object | Export-Csv -LiteralPath $ResultsPath -NoTypeInformation -Encoding UTF8
    }
}

function Invoke-OhsimTest {
    param([System.IO.Ports.SerialPort]$Serial, [int]$Id)
    $key = $TestNames[$Id]
    $instrumentDir = Join-Path $OutputDir $key
    New-Item -ItemType Directory -Force -Path $instrumentDir | Out-Null
    Write-Host "`n=== $key / TEST $Id ===" -ForegroundColor Cyan
    Write-Host "Guardar ILA/Rigol en: $instrumentDir" -ForegroundColor DarkCyan
    Send-ProtocolCommand $Serial 'SAFE' | Out-Null
    Send-ProtocolCommand $Serial "PREPARE $Id" | Out-Null
    Wait-ProtocolEvent $Serial 'ARMED' $Id 3.0 | Out-Null

    if ($ArmPrompt) {
        Read-Host "$key ARMED. Arme ILA/osciloscopio; Enter aplica el escalon"
    }

    Send-ProtocolCommand $Serial 'RUN' | Out-Null
    $done = Wait-ProtocolEvent $Serial 'DONE' $Id 3.0
    $response = Send-ProtocolCommand $Serial 'RESULT'
    $result = ConvertFrom-ProtocolFields $response
    if (-not $result.ContainsKey('TEST') -or [int]$result['TEST'] -ne $Id) {
        throw "RESULT no corresponde a TEST $Id`: $response"
    }
    if (-not $result.ContainsKey('RESULT') -or -not $result.ContainsKey('SAMPLES')) {
        throw "RESULT incompleto: $response"
    }
    if ($done.ContainsKey('RESULT') -and $done['RESULT'] -ne $result['RESULT']) {
        throw "Veredicto inconsistente: evento=$($done['RESULT']), RESULT=$($result['RESULT'])."
    }
    Save-Result $result
    Send-ProtocolCommand $Serial 'SAFE' | Out-Null

    if ($ArmPrompt) {
        Read-Host "$key DONE y SAFE. Exporte Rigol/ILA a $instrumentDir; Enter continua"
    }
}

$serial = New-Object System.IO.Ports.SerialPort
$serial.PortName = $Port
$serial.BaudRate = $Baud
$serial.Parity = [System.IO.Ports.Parity]::None
$serial.DataBits = 8
$serial.StopBits = [System.IO.Ports.StopBits]::One
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.NewLine = "`n"
$serial.ReadTimeout = 100
$serial.WriteTimeout = 1000
$serial.DtrEnable = $false
$serial.RtsEnable = $false

try {
    $serial.Open()
    Start-Sleep -Milliseconds 150
    $serial.DiscardInBuffer()
    Write-Host 'Inicializando estado seguro y calibrando ceros ADC...' -ForegroundColor DarkCyan
    Send-ProtocolCommand $serial 'SAFE' | Out-Null
    Start-Sleep -Milliseconds 1000
    $calibration = Send-ProtocolCommand $serial 'CAL ZERO' 3.0
    if ($calibration -notmatch '^OK CAL=ZERO ') {
        throw "CAL ZERO no fue confirmado: $calibration"
    }
    $ids = if ($All) { $TestOrder } else { @($TestId) }
    foreach ($id in $ids) {
        try {
            Invoke-OhsimTest $serial $id
        }
        catch {
            try { Send-ProtocolCommand $serial 'SAFE' 1.0 | Out-Null } catch {}
            throw
        }
    }
    Write-Host "`nResultados: $ResultsPath" -ForegroundColor Green
    Write-Host "Transcript: $TranscriptPath" -ForegroundColor Green
}
finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
