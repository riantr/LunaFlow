<#
.SYNOPSIS
  The LOCAL GATE, and what each check's exit code MEANS.

.DESCRIPTION
  THREE VERDICTS, NOT TWO.

  A check can end in three ways, and the gate must not confuse them:

    exit 0   the check ran, and every claim it makes agreed.        PASS
    exit 1   the check ran, and a claim did NOT agree.               FAIL
    exit 2   the check could NOT produce a verdict at all.         UNKNOWN

  The third one is why this file exists.  A check that cannot RUN -- the
  registry is unreachable, the analyser wrote no findings, the build
  failed, there is nothing to compare -- says NOTHING about the tree.
  Reading it as a failure says "the module is broken" when the truth is
  "nobody knows", and that is a false accusation: it is exactly what
  `core_compat.mjs` warned about when the registry's newest core could not
  be fetched -- "its compatibility is UNKNOWN rather than broken".

  THE CONVENTION IS NOT NEW, AND IT IS NOT THIS FILE'S.  The harnesses under
  `scripts/qa/` ALREADY use exit 2 for "no verdict" -- 28 sites across 17
  scripts -- and exit 1 for "the checks failed".  What was missing was a gate
  that READS it: the old runner counted every non-zero exit as a failure, so
  "I could not verify" was printed as `FAIL(2)` and weighed the same as a
  real defect.

  SO THE GATE'S OWN VERDICT IS:

    0   every check passed
    1   at least one check FAILED -- the tree is broken, fix it
    2   no check failed, but at least one could NOT BE VERIFIED -- the tree
        is NOT known to be broken; re-run when the environment is back

  An UNKNOWN still BLOCKS.  A release whose interface check could not run is
  not a release.  What changes is the WORDING, and the exit code a CI can
  read to tell "broken" from "unverified" -- so the two are never confused.

  AN UNEXPECTED EXIT CODE IS A FAIL.  A code that is neither 0, 1 nor 2
  means the check did not behave as documented, and the gate fails closed.

  The verdict of every step is also written as a line, so the whole run can
  be read without scrolling: `ok`, `FAIL(n)` and `UNKNOWN(2)`.

.PARAMETER Steps
  A JSON file holding the step list: an array of command strings.  The
  default is `scripts/qa/gate-steps.json`, the LOCAL list -- the toolchain
  and the harnesses, on this machine.  The CI has its own per-step list in
  `.github/workflows/ci.yml`, because the CI runner installs a different
  toolchain and a different PATH.

.PARAMETER ListOnly
  Resolve the step list, print it, and STOP -- without running a single
  check.  This is how the DEFAULT list is tested: the path the runner
  builds for itself has to work on the platform the runner is ON, and a
  path built with a Windows separator does not (a backslash is an ordinary
  character in a file name on Linux).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\qa\gate.ps1

.EXAMPLE
  pwsh -NoProfile -File scripts/qa/gate.ps1 -ListOnly

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\qa\gate.ps1 -Steps _build\qa\fixture.json
#>
param(
  [string]$Steps = '',
  [switch]$ListOnly
)

$ErrorActionPreference = 'Continue'

# The repository root, so the gate runs the same way from any directory.
$here = Split-Path -Parent $PSScriptRoot   # <repo>/scripts
$root = Split-Path -Parent $here            # <repo>
Set-Location -LiteralPath $root

# The default is built with NESTED Join-Path calls, never with a literal
# separator: a backslash is a separator on Windows and an ordinary character
# in a file name on Linux, where `Join-Path $here 'qa\gate-steps.json'`
# produces a path that does not exist and the runner finds no step list at
# all.  Join-Path always uses the platform's own separator.
if ($Steps -eq '') { $Steps = Join-Path (Join-Path $here 'qa') 'gate-steps.json' }
if (-not (Test-Path -LiteralPath $Steps)) {
  Write-Error "the step list does not exist: $Steps"
  exit 2
}
$parsed = Get-Content -Raw -LiteralPath $Steps | ConvertFrom-Json

# The list is collected with an explicit `foreach`, NOT with `@(...)`:
# PowerShell 5.1 hands ConvertFrom-Json's ARRAY over as ONE object, so `@(...)`
# around it nests the array inside a one-element array -- the gate then ran
# all three steps as one joined command and called it a single failure.
$list = @()
foreach ($item in $parsed) { $list += [string]$item }
if ($list.Count -eq 0) {
  Write-Error "the step list is empty: $Steps"
  exit 2
}
Write-Output "the gate: $($list.Count) step(s), from $Steps"

# Resolve the list and stop.  The step list is printed so the caller can
# compare it with the list it thinks is shipped -- which is how the DEFAULT
# list is checked without running the whole gate.
if ($ListOnly) {
  foreach ($s in $list) { Write-Output "  step: $s" }
  exit 0
}

$results = @()
foreach ($s in $list) {
  $out = Invoke-Expression $s 2>&1 | Out-String
  $code = $LASTEXITCODE

  # ONE classification, used for the line that is printed, for the summary
  # counts and for the gate's own exit code.  Deciding the verdict twice --
  # once for the wording and once for the counting -- lets the two disagree,
  # and a gate whose own output contradicts its own exit code is worse than
  # no gate.
  $verdict = 'fail'
  if ($code -eq 0) { $verdict = 'pass' }
  elseif ($code -eq 2) { $verdict = 'unknown' }

  $results += [PSCustomObject]@{ cmd = $s; code = $code; verdict = $verdict; out = $out }
  if ($verdict -eq 'pass') {
    Write-Output "ok          $s"
  } elseif ($verdict -eq 'unknown') {
    Write-Output "UNKNOWN(2)  $s"
  } elseif ($null -eq $code) {
    # The command did not run at all, so there was no exit code to read.
    Write-Output "FAIL(none)  $s"
  } else {
    Write-Output "FAIL($code)  $s"
  }
}

$pass = @($results | Where-Object { $_.verdict -eq 'pass' })
$fail = @($results | Where-Object { $_.verdict -eq 'fail' })
$unk = @($results | Where-Object { $_.verdict -eq 'unknown' })

Write-Output ''
if ($fail.Count -gt 0) {
  Write-Output '== FAILED: the check ran, and the tree did not agree =='
  foreach ($r in $fail) {
    Write-Output "  $($r.cmd)   (exit $($r.code))"
    # THE REASON IS PART OF THE FAILURE, and it was being filtered out.
    #
    # A harness prints its verdict on one line and the REASON on the indented
    # lines under it -- that is the convention in this harness, and it is what
    # `gherkin.mjs` does.  A filter that keeps only the verdict therefore
    # printed the command and the exit code and nothing else: the summary of
    # the gherkin step in the failed 54-step release gate said
    # `FAIL  <scenario>` and named no cause at all.  MEASURED with this
    # filter, read out of this file: three reason lines, zero survive.
    #
    # So the indented lines under a verdict are kept WITH it.
    #
    # `FIX` is in the filter because a remedy line IS part of the failure: a
    # check that says what is wrong and prints the command that fixes it must
    # not have that command filtered out of the summary.
    #
    # It is anchored at the START of the line, and it has to be: the word
    # "fixture" contains "fix", so a looser anchor read every harness line
    # that mentioned the demo fixture as a remedy -- and the run_artefacts
    # helper, the feature files and the e2e harness all say "fixture".  The
    # remedy lines are printed at the start of the line, so `^FIX` is exact.
    $kept = @()
    $all = $r.out -split "`n"
    for ($i = 0; $i -lt $all.Count -and $kept.Count -lt 12; $i++) {
      $line = $all[$i]
      if ($line -notmatch 'FAIL|error|Error|not ok|^FIX') { continue }
      $kept += $line
      $j = $i + 1
      while ($j -lt $all.Count -and $kept.Count -lt 12 -and $all[$j] -match '^\s+\S') {
        $kept += $all[$j]
        $j++
      }
    }
    $kept | ForEach-Object {
      Write-Output "        $_"
    }
  }
  Write-Output ''
}
if ($unk.Count -gt 0) {
  Write-Output '== UNKNOWN: the check could not produce a verdict -- the tree is NOT known to be broken =='
  foreach ($r in $unk) {
    Write-Output "  $($r.cmd)   (exit 2)"
    $r.out -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 4 | ForEach-Object {
      Write-Output "        $_"
    }
  }
  Write-Output ''
}

Write-Output "GATE: $($pass.Count) passed, $($fail.Count) failed, $($unk.Count) unknown (could not be verified)"

if ($fail.Count -gt 0) { exit 1 }
if ($unk.Count -gt 0) { exit 2 }
exit 0
