# PowerShell Tool Tests

This directory contains automated contract tests for the PowerShell scripts under `tools/`.

## Prerequisite

- PowerShell 7+
- Pester 5+

## Run the suite

```powershell
pwsh ./tools/tests/run-tool-tests.ps1
```

## Coverage

- `tools/validate-json.ps1`: schema pass/fail behavior, malformed JSON handling, relative and absolute path resolution, and pass-through output.
- `tools/evidence/new-evidence-manifest.ps1`: manifest generation from seeded fixtures, explicit overrides, partial bundles, output directory creation, and required-input failures.
- `tools/evidence/validate-evidence-manifest.ps1`: canonical valid and invalid fixtures, missing artifact detection, and out-of-repo artifact rejection.
- `tools/automation/validate-write-boundary.ps1`: allowed writes, boundary violations, artifact lookup failures, count mismatch failures, and absolute-path normalization.
- `tools/automation/new-autonomous-run-record.ps1`: schema-valid record emission, parent directory creation, default field materialization, and parameter count validation.

## Script Test Manifest

See `tools/tests/SCRIPT_TEST_MANIFEST.md` for the script-by-script test matrix and the fixtures each suite consumes.