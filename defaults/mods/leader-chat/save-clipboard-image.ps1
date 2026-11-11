[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$SpaceId
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not [Windows.Forms.Clipboard]::ContainsImage()) {
    throw 'Clipboard does not contain an image.'
}

$environmentRoot = if ($env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT) {
    [IO.Path]::GetFullPath($env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT)
} else {
    Join-Path $env:LOCALAPPDATA 'Nauagency\Multi Agent Herdr\agent-environments'
}
$attachmentRoot = Join-Path (Join-Path (Join-Path $environmentRoot 'space-jobs') 'attachments') $SpaceId
New-Item -ItemType Directory -Path $attachmentRoot -Force | Out-Null
$name = 'chat-{0}-{1}.png' -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$path = Join-Path $attachmentRoot $name
$bitmap = [Windows.Forms.Clipboard]::GetImage()
try { $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png) }
finally { if ($null -ne $bitmap) { $bitmap.Dispose() } }

[ordered]@{ path = $path } | ConvertTo-Json -Compress
