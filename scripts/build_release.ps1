# Release build helper (Windows PowerShell). Run from the repo root:
#   powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1
#
# - Dart obfuscation + split debug info (symbols are written OUTSIDE the app bundle)
# - Your real keys come from env.local.json (gitignored; copy .env.example, never commit)
# - Needs android\key.properties for an uploadable build; without it Gradle signs with the DEBUG key
#   and prints a warning (such a bundle is NOT uploadable to Google Play).
#
# KEEP the symbols folder of every build you ship (symbols\<version>): without it obfuscated
# crash stack traces cannot be read.  Decode a stack trace with:
#   flutter symbolize -i stack.txt -d symbols\<version>

$ErrorActionPreference = "Stop"
$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$symbols = "symbols\$version"
New-Item -ItemType Directory -Force -Path $symbols | Out-Null

# Mock billing is debug-only; never let it near a release build.
if ((Test-Path env.local.json) -and ((Get-Content env.local.json -Raw) -match 'MOCK_BILLING')) {
  throw "env.local.json contains MOCK_BILLING. Remove it: mock billing is debug-only."
}

$defines = @()
if (Test-Path env.local.json) { $defines += "--dart-define-from-file=env.local.json" }
else { Write-Warning "env.local.json not found: cloud, subscriptions and videos will be disabled in this build." }

flutter build appbundle --release --obfuscate "--split-debug-info=$symbols" @defines
flutter build apk --split-per-abi --release --obfuscate "--split-debug-info=$symbols" @defines

Write-Host "Done. Bundle: build\app\outputs\bundle\release\app-release.aab"
Write-Host "Archive $symbols somewhere safe (NOT inside the app)."
