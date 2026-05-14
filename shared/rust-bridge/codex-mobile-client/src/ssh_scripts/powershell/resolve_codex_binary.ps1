# Find an existing codex binary on a Windows remote and emit
# "codex:<path>" to stdout, or nothing if not found.
$found = Get-Command codex -ErrorAction SilentlyContinue
if ($found) { Write-Output "codex:$($found.Source)"; exit 0 }
