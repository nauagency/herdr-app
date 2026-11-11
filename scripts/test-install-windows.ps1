$ErrorActionPreference = "Stop"
. "$PSScriptRoot\install-windows.ps1"

function Assert($Condition, $Message) {
    if (-not $Condition) { throw $Message }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) "herdr-install-test-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $binary = Join-Path $tmp "build.exe"
    $core = Join-Path $tmp "core.exe"
    $conpty = Join-Path $tmp "conpty"
    $icon = Join-Path $tmp "icon.svg"
    $destination = Join-Path $tmp "Programs\herdr-app"
    Set-Content -LiteralPath $binary -Value "first build"
    Set-Content -LiteralPath $core -Value "core build"
    New-Item -ItemType Directory -Path $conpty | Out-Null
    Set-Content -LiteralPath (Join-Path $conpty "conpty.dll") -Value "conpty"
    Set-Content -LiteralPath $icon -Value "icon"
    Install-HerdrAppFiles $binary $core $conpty $icon $destination
    Assert ((Get-Content "$destination\multi-agent-herdr.exe") -eq "first build") "First install lost the binary"
    Assert ((Get-Content "$destination\multi-agent-herdr.svg") -eq "icon") "First install lost the icon"
    Assert ((Get-Content "$destination\multi-agent-herdr-core.exe") -eq "core build") "First install lost the core"
    Assert ((Get-Content "$destination\hc.exe") -eq "core build") "First install lost the core CLI alias"

    Set-Content -LiteralPath $binary -Value "new build"
    Install-HerdrAppFiles $binary $core $conpty $icon $destination
    Assert ((Get-Content "$destination\multi-agent-herdr.exe") -eq "new build") "Replacement kept the old binary"
    Assert ((Get-ChildItem (Split-Path $destination)).Count -eq 1) "Replacement left temporary files"

    # Fail the promotion, then the rollback too, using real moves otherwise.
    function Rename-Item {
        param($LiteralPath, $NewName)
        $script:moves++
        if ($script:failMoves -contains $script:moves) { throw "injected move failure $script:moves" }
        Microsoft.PowerShell.Management\Rename-Item -LiteralPath $LiteralPath -NewName $NewName
    }
    foreach ($failures in @(@(2), @(2, 3))) {
        $script:moves = 0
        $script:failMoves = $failures
        $errorText = $null
        try { Install-HerdrAppFiles $binary $core $conpty $icon $destination }
        catch { $errorText = $_.ToString() }
        Assert ($null -ne $errorText) "Failed installation reported success"
        if ($failures.Count -eq 1) {
            Assert ((Get-Content "$destination\multi-agent-herdr.exe") -eq "new build") "Rollback lost the previous build"
        } else {
            $backup = Get-ChildItem (Split-Path $destination) -Directory -Filter "herdr-app.old-*"
            Assert ($backup.Count -eq 1) "Failed rollback lost the backup"
            Assert ($errorText.Contains($backup.FullName)) "Failed rollback did not report the backup path"
            Assert ((Get-Content "$($backup.FullName)\multi-agent-herdr.exe") -eq "new build") "Failed rollback damaged the backup"
        }
        Assert (-not (Get-ChildItem (Split-Path $destination) -Directory -Filter "herdr-app.install-*")) "Failed install left staging files"
    }
    Write-Host "Installer file replacement and rollback checks passed."
} finally {
    Remove-Item Function:Rename-Item -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force
}
