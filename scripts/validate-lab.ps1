param(
    [string]$ResourceGroup = "rg-aumlab",
    [string]$SubscriptionId
)

# Reuse an existing Az session if there is one; sign in otherwise.
if (-not (Get-AzContext -ErrorAction SilentlyContinue)) { Connect-AzAccount | Out-Null }
if ($SubscriptionId) { Set-AzContext -SubscriptionId $SubscriptionId | Out-Null }

$vms     = @("DC01", "WS01", "WS02")
$results = @()
$allPass = $true

Write-Host "`n=== Azure Update Manager Compliance Validation ===" -ForegroundColor Cyan

foreach ($vm in $vms) {
    # The latest assessment lives in the VM instance view:
    #   PatchStatus.AvailablePatchSummary
    $summary = $null
    try {
        $view    = Get-AzVM -ResourceGroupName $ResourceGroup -Name $vm -Status -ErrorAction Stop
        $summary = $view.PatchStatus.AvailablePatchSummary
    } catch {
        Write-Host "[FAIL] $vm -- could not read VM: $($_.Exception.Message)" -ForegroundColor Red
    }

    $status   = $summary.Status
    $critical = $summary.CriticalAndSecurityPatchCount

    # PASS = assessment finished AND no Critical/Security patches missing.
    # A brand-new VM usually FAILS - it has patches outstanding. That's expected.
    $assessed  = $status -in @("Succeeded", "CompletedWithWarnings")
    $compliant = $assessed -and ($critical -eq 0)
    $result    = if ($compliant) { "PASS" } else { "FAIL" }
    if (-not $compliant) { $allPass = $false }

    $color = if ($compliant) { "Green" } else { "Yellow" }
    Write-Host ("[{0}] {1} -- Critical/Security missing: {2} | Other: {3} | Status: {4} | Reboot pending: {5}" -f `
        $result, $vm, $critical, $summary.OtherPatchCount, $status, $summary.RebootPending) -ForegroundColor $color

    $results += [PSCustomObject]@{
        VMName                   = $vm
        AssessmentStatus         = $status
        CriticalAndSecurityCount = $critical
        OtherPatchCount          = $summary.OtherPatchCount
        RebootPending            = $summary.RebootPending
        LastAssessmentTime       = $summary.LastModifiedTime
        Compliant                = $compliant
        Result                   = $result
    }
}

Write-Host ""
Write-Host "Overall: $(if ($allPass) {'ALL PASS'} else {'FAILURES DETECTED'})" `
    -ForegroundColor $(if ($allPass) {"Green"} else {"Red"})

# Machine-readable export - what you'd feed a SIEM, ServiceNow, or a dashboard.
$report = [ordered]@{
    GeneratedAt   = (Get-Date -Format "o")
    ResourceGroup = $ResourceGroup
    AllCompliant  = $allPass
    VMs           = $results
}
$report | ConvertTo-Json -Depth 5 | Out-File "./aum-compliance-report.json" -Encoding UTF8
Write-Host "Report exported: aum-compliance-report.json" -ForegroundColor Cyan
