# Loads the legacy database on Windows from load-order.txt, with Windows authentication.
# Used by CI (legacy.yml); the EC2 boot script reuses it.
#
#   ./legacy/database/load.ps1          load into a server without a PurchaseDesk database
#   ./legacy/database/load.ps1 -Fresh   drop PurchaseDesk first, then load: every test suite starts from the seed
param(
    [switch]$Fresh,
    [string]$Server = 'localhost'
)

$ErrorActionPreference = 'Stop'

if ($Fresh) {
    Write-Host "Dropping PurchaseDesk"
    sqlcmd -S $Server -E -b -Q "IF DB_ID(N'PurchaseDesk') IS NOT NULL BEGIN ALTER DATABASE PurchaseDesk SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE PurchaseDesk; END"
    if ($LASTEXITCODE -ne 0) { throw "Dropping PurchaseDesk failed" }
}

Get-Content (Join-Path $PSScriptRoot 'load-order.txt') |
    Where-Object { $_.Trim() -and -not $_.StartsWith('#') } |
    ForEach-Object {
        Write-Host "Loading $_"
        sqlcmd -S $Server -E -b -i (Join-Path $PSScriptRoot $_)
        if ($LASTEXITCODE -ne 0) { throw "Loading $_ failed" }
    }
