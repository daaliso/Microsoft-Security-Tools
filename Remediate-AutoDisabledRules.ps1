#Requires -Version 5.0
<#
.SYNOPSIS
    Microsoft Sentinel Auto-Disabled Analytics Rule Remediation Tool

.DESCRIPTION
    Interactive CLI tool that identifies analytics rules automatically disabled 
    by Microsoft Sentinel due to consecutive failures, and provides remediation 
    to restore them to their original working state.

.FEATURES
    - Scans for all AUTO DISABLED analytics rules in a workspace
    - Displays disable reasons from rule descriptions
    - Selective or bulk remediation workflow
    - Restores original rule names and descriptions
    - Re-enables rules after remediation

.REQUIREMENTS
    - PowerShell 5.0 or higher
    - Az.Accounts module
    - Az.Resources module  
    - Az.OperationalInsights module
    - Microsoft Sentinel Contributor permissions for remediation

.AUTHOR
    Daliso Tembo

.VERSION
    1.0.0
#>

# ============================================================================
# MODULE CHECK AND INSTALLATION
# ============================================================================

function Test-RequiredModules {
    $requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.OperationalInsights')
    $missingModules = @()
    
    Write-Host ""
    Write-Host "  Checking required PowerShell modules..." -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($module in $requiredModules) {
        Write-Host "  Checking for $module..." -NoNewline
        $installed = Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue
        
        if ($installed) {
            Write-Host " [OK]" -ForegroundColor Green
        }
        else {
            Write-Host " [MISSING]" -ForegroundColor Red
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Host ""
        Write-Host "  Missing modules detected: $($missingModules -join ', ')" -ForegroundColor Yellow
        Write-Host ""
        
        $install = Read-Host "  Would you like to install missing modules? (Y/N)"
        
        if ($install -eq 'Y' -or $install -eq 'y') {
            foreach ($module in $missingModules) {
                Write-Host ""
                Write-Host "  Installing $module..." -ForegroundColor Cyan
                try {
                    Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
                    Write-Host "  $module installed successfully" -ForegroundColor Green
                }
                catch {
                    Write-Host "  Failed to install ${module}: $_" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "  Please install manually using: Install-Module -Name $module -Scope CurrentUser" -ForegroundColor Yellow
                    return $false
                }
            }
            Write-Host ""
            Write-Host "  All modules installed successfully!" -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "  Cannot proceed without required modules. Exiting." -ForegroundColor Red
            return $false
        }
    }
    
    # Import the modules to ensure they're loaded into the current session
    Write-Host ""
    Write-Host "  Loading modules..." -ForegroundColor Cyan
    foreach ($module in $requiredModules) {
        try {
            Import-Module -Name $module -ErrorAction Stop
        }
        catch {
            Write-Host "  Failed to load ${module}: $_" -ForegroundColor Red
            return $false
        }
    }
    Write-Host "  Modules loaded successfully" -ForegroundColor Green
    
    return $true
}

# ============================================================================
# UI HELPER FUNCTIONS
# ============================================================================

function Show-Banner {
    Write-Host ""
    Write-Host "  ██████╗ ██╗███████╗ █████╗ ██████╗ ██╗     ███████╗██████╗ " -ForegroundColor Cyan
    Write-Host "  ██╔══██╗██║██╔════╝██╔══██╗██╔══██╗██║     ██╔════╝██╔══██╗" -ForegroundColor Cyan
    Write-Host "  ██║  ██║██║███████╗███████║██████╔╝██║     █████╗  ██║  ██║" -ForegroundColor DarkCyan
    Write-Host "  ██║  ██║██║╚════██║██╔══██║██╔══██╗██║     ██╔══╝  ██║  ██║" -ForegroundColor DarkCyan
    Write-Host "  ██████╔╝██║███████║██║  ██║██████╔╝███████╗███████╗██████╔╝" -ForegroundColor Blue
    Write-Host "  ╚═════╝ ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝╚═════╝ " -ForegroundColor Blue
    Write-Host ""
    Write-Host "  ██████╗ ██╗   ██╗██╗     ███████╗    ██████╗ ███████╗███████╗████████╗ ██████╗ ██████╗ ███████╗" -ForegroundColor Magenta
    Write-Host "  ██╔══██╗██║   ██║██║     ██╔════╝    ██╔══██╗██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝" -ForegroundColor Magenta
    Write-Host "  ██████╔╝██║   ██║██║     █████╗      ██████╔╝█████╗  ███████╗   ██║   ██║   ██║██████╔╝█████╗  " -ForegroundColor DarkMagenta
    Write-Host "  ██╔══██╗██║   ██║██║     ██╔══╝      ██╔══██╗██╔══╝  ╚════██║   ██║   ██║   ██║██╔══██╗██╔══╝  " -ForegroundColor DarkMagenta
    Write-Host "  ██║  ██║╚██████╔╝███████╗███████╗    ██║  ██║███████╗███████║   ██║   ╚██████╔╝██║  ██║███████╗" -ForegroundColor DarkMagenta
    Write-Host "  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝    ╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝" -ForegroundColor DarkMagenta
    Write-Host ""
    Write-Host "  Microsoft Sentinel Auto-Disabled Analytics Rule Remediation Tool v1.0" -ForegroundColor Gray
    Write-Host "  ─────────────────────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-Menu {
    param(
        [string]$Title,
        [string[]]$Options,
        [string]$Subtitle = "",
        [switch]$ShowNumbers
    )
    
    $selected = 0
    $done = $false
    $numberInput = ""
    
    while (-not $done) {
        Clear-Host
        Show-Banner
        
        Write-Host "  $Title" -ForegroundColor Yellow
        if ($Subtitle) {
            Write-Host "  $Subtitle" -ForegroundColor DarkGray
        }
        Write-Host ""
        
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $prefix = if ($ShowNumbers) { "[$i] " } else { "" }
            
            if ($i -eq $selected) {
                Write-Host "  ▶ " -NoNewline -ForegroundColor Green
                Write-Host "$prefix$($Options[$i])" -ForegroundColor White -BackgroundColor DarkGray
            }
            else {
                Write-Host "    $prefix$($Options[$i])" -ForegroundColor Gray
            }
        }
        
        Write-Host ""
        if ($ShowNumbers) {
            Write-Host "  Use ↑↓ arrows or type number, then Enter" -ForegroundColor DarkGray
            if ($numberInput) {
                Write-Host "  Input: $numberInput" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "  Use ↑↓ arrows to navigate, Enter to select" -ForegroundColor DarkGray
        }
        
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        if ($ShowNumbers -and $key.Character -match '\d') {
            $numberInput += $key.Character
            $num = [int]$numberInput
            if ($num -ge 0 -and $num -lt $Options.Count) {
                $selected = $num
            }
            continue
        }
        
        if ($ShowNumbers -and $key.VirtualKeyCode -eq 8 -and $numberInput.Length -gt 0) {
            $numberInput = $numberInput.Substring(0, $numberInput.Length - 1)
            if ($numberInput) {
                $num = [int]$numberInput
                if ($num -ge 0 -and $num -lt $Options.Count) {
                    $selected = $num
                }
            }
            continue
        }
        
        switch ($key.VirtualKeyCode) {
            38 { $selected = ($selected - 1); if ($selected -lt 0) { $selected = $Options.Count - 1 }; $numberInput = "" }
            40 { $selected = ($selected + 1) % $Options.Count; $numberInput = "" }
            13 { $done = $true }
        }
    }
    
    return $selected
}

function Show-Status {
    param(
        [string]$Message,
        [ValidateSet("Success", "Error", "Warning", "Info")]
        [string]$Type = "Info"
    )
    
    $color = "Cyan"
    $icon = switch ($Type) {
        "Success" { "+"; $color = "Green" }
        "Error" { "x"; $color = "Red" }
        "Warning" { "!"; $color = "Yellow" }
        "Info" { "i"; $color = "Cyan" }
    }
    
    Write-Host "  $icon " -NoNewline -ForegroundColor $color
    Write-Host $Message -ForegroundColor Gray
}

# ============================================================================
# AZURE AUTHENTICATION
# ============================================================================

function Test-AzureAuthentication {
    Show-Status "Checking Azure authentication..." -Type Info
    
    $context = Get-AzContext -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    
    if (-not $context) {
        return $false
    }
    
    Show-Status "Authenticated as: $($context.Account.Id)" -Type Success
    return $true
}

function Connect-ToAzure {
    $authOptions = @(
        "Authenticate now",
        "Use existing authentication"
    )
    
    $authChoice = Show-Menu -Title "Step 1: Authentication" -Options $authOptions -Subtitle "Choose your authentication method"
    
    if ($authChoice -eq 0) {
        Clear-Host
        Show-Banner
        Write-Host "  Authenticating..." -ForegroundColor Yellow
        Write-Host ""
        
        $tenantId = Read-Host "  Enter Tenant ID (or press Enter for interactive authentication)"
        
        $env:AZURE_CORE_DISABLE_WAM = "true"
        
        try {
            if ([string]::IsNullOrWhiteSpace($tenantId)) {
                Connect-AzAccount -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Connect-AzAccount -TenantId $tenantId -WarningAction SilentlyContinue | Out-Null
            }
            Show-Status "Authentication successful" -Type Success
            return $true
        }
        catch {
            Show-Status "Authentication failed: $_" -Type Error
            return $false
        }
    }
    else {
        if (Test-AzureAuthentication) {
            return $true
        }
        else {
            Show-Status "Not authenticated. Please authenticate first." -Type Error
            return $false
        }
    }
}

# ============================================================================
# AZURE RESOURCE SELECTION
# ============================================================================

function Select-Subscription {
    $subscriptions = Get-AzSubscription -WarningAction SilentlyContinue
    if ($subscriptions.Count -eq 0) {
        Show-Status "No subscriptions found." -Type Error
        return $null
    }
    
    $subOptions = $subscriptions | ForEach-Object { "$($_.Name)" }
    $subIndex = Show-Menu -Title "Step 2: Select Subscription" -Options $subOptions -Subtitle "Choose your Azure subscription" -ShowNumbers
    
    $selectedSubscription = $subscriptions[$subIndex]
    Set-AzContext -Subscription $selectedSubscription.Id -WarningAction SilentlyContinue | Out-Null
    
    return $selectedSubscription
}

function Select-ResourceGroup {
    $resourceGroups = Get-AzResourceGroup -WarningAction SilentlyContinue | Sort-Object ResourceGroupName
    if ($resourceGroups.Count -eq 0) {
        Show-Status "No resource groups found." -Type Error
        return $null
    }
    
    $rgOptions = $resourceGroups | ForEach-Object { $_.ResourceGroupName }
    $rgIndex = Show-Menu -Title "Step 3: Select Resource Group" -Options $rgOptions -Subtitle "Choose your resource group" -ShowNumbers
    
    return $resourceGroups[$rgIndex].ResourceGroupName
}

function Select-Workspace {
    param([string]$ResourceGroupName)
    
    $workspaces = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -WarningAction SilentlyContinue
    if ($workspaces.Count -eq 0) {
        Show-Status "No workspaces found in resource group '$ResourceGroupName'." -Type Error
        return $null
    }
    
    if ($workspaces -is [array]) {
        $wsOptions = $workspaces | ForEach-Object { $_.Name }
        $wsIndex = Show-Menu -Title "Step 4: Select Workspace" -Options $wsOptions -Subtitle "Choose your Log Analytics workspace"
        return $workspaces[$wsIndex].Name
    }
    else {
        return $workspaces.Name
    }
}

# ============================================================================
# AUTO DISABLED RULE DETECTION AND REMEDIATION
# ============================================================================

function Get-AutoDisabledRules {
    param(
        [string]$ResourceGroupName,
        [string]$WorkspaceName,
        [hashtable]$AuthHeader,
        [string]$SubscriptionId
    )
    
    Show-Status "Scanning for AUTO DISABLED analytics rules..." -Type Info
    
    try {
        $baseUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/"
        $uri = $baseUrl + "alertRules?api-version=2023-12-01-preview"
        
        $response = Invoke-RestMethod -Method "Get" -Uri $uri -Headers $AuthHeader
        $allRules = $response.value
        
        $totalRulesCount = if ($allRules) { $allRules.Count } else { 0 }
        Show-Status "Found $totalRulesCount total analytics rules" -Type Info
        
        # Filter for AUTO DISABLED rules
        $autoDisabledRules = $allRules | Where-Object {
            $_.properties.displayName -like "AUTO DISABLED *"
        }
        
        $autoDisabledCount = if ($autoDisabledRules) { @($autoDisabledRules).Count } else { 0 }
        $statusType = if ($autoDisabledCount -gt 0) { "Warning" } else { "Success" }
        Show-Status "Found $autoDisabledCount AUTO DISABLED rules" -Type $statusType
        
        if ($autoDisabledCount -eq 0) {
            return , @()
        }
        
        $rulesWithReasons = @()
        foreach ($rule in $autoDisabledRules) {
            $disableReason = "Unknown"
            $originalDescription = ""
            
            if ($rule.properties.description) {
                $desc = $rule.properties.description
                
                # Known Sentinel disable reasons
                $knownReasons = @(
                    'The query was blocked as it was consuming too many resources',
                    'The target table \(on which the rule query operated\) was deleted',
                    'Permissions to one of the data sources of the rule query were changed',
                    'Insufficient access to resource',
                    'A function used by the rule query is no longer valid',
                    'Microsoft Sentinel was removed from the target workspace',
                    'One of the data sources of the rule query were disconnected'
                )
                
                $foundReason = $false
                foreach ($reason in $knownReasons) {
                    if ($desc -match $reason) {
                        $disableReason = $reason -replace '\\', ''
                        $foundReason = $true
                        break
                    }
                }
                
                if (-not $foundReason) {
                    if ($desc -match 'Reason:\s*([^.]+)\.') {
                        $disableReason = $matches[1].Trim()
                    }
                    elseif ($desc -match 'disabled\s+due\s+to\s+([^.]+)\.') {
                        $disableReason = $matches[1].Trim()
                    }
                }
                
                # Extract original description by removing known failure messages
                $failurePrefix = "The alert rule was disabled due to too many consecutive failures."
                
                # Known Sentinel failure reason messages
                $knownReasonStrings = @(
                    "Reason: The query was blocked as it was consuming too many resources.",
                    "Reason: The target table (on which the rule query operated) was deleted.",
                    "Reason: Permissions to one of the data sources of the rule query were changed.",
                    "Reason: Insufficient access to resource.",
                    "Reason: A function used by the rule query is no longer valid.",
                    "Reason: Microsoft Sentinel was removed from the target workspace.",
                    "Reason: One of the data sources of the rule query were disconnected."
                )
                
                $cleanedDesc = $desc
                
                $cleanedDesc = $cleanedDesc -replace [regex]::Escape($failurePrefix), ''
                
                foreach ($reasonStr in $knownReasonStrings) {
                    $cleanedDesc = $cleanedDesc -replace [regex]::Escape($reasonStr), ''
                }
                
                $cleanedDesc = $cleanedDesc -replace '^\s*[\n\r]+', ''
                $cleanedDesc = $cleanedDesc.Trim()
                
                if (-not [string]::IsNullOrWhiteSpace($cleanedDesc)) {
                    $originalDescription = $cleanedDesc
                }
            }
            
            $rulesWithReasons += [PSCustomObject]@{
                RuleId              = $rule.name
                DisplayName         = $rule.properties.displayName
                OriginalName        = $rule.properties.displayName -replace '^AUTO DISABLED\s*', ''
                Description         = $rule.properties.description
                OriginalDescription = $originalDescription
                DisableReason       = $disableReason
                Enabled             = $rule.properties.enabled
                Kind                = $rule.kind
                RuleObject          = $rule
            }
        }
        
        return $rulesWithReasons
    }
    catch {
        Show-Status "Failed to retrieve analytics rules: $_" -Type Error
        return $null
    }
}

function Show-AutoDisabledRulesSummary {
    param([array]$Rules)
    
    Write-Host ""
    Write-Host "  ═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "                    AUTO DISABLED RULES FOUND                         " -ForegroundColor Cyan
    Write-Host "  ═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "  Total AUTO DISABLED Rules: $($Rules.Count)" -ForegroundColor Yellow
    Write-Host ""
    
    # Group by disable reason
    $groupedByReason = $Rules | Group-Object -Property DisableReason | Sort-Object Count -Descending
    
    Write-Host "  Disable Reasons:" -ForegroundColor Cyan
    Write-Host "  ───────────────" -ForegroundColor DarkGray
    foreach ($group in $groupedByReason) {
        Write-Host "    • $($group.Name): $($group.Count) rule(s)" -ForegroundColor Gray
    }
    Write-Host ""
    
    Write-Host "  ═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Detailed Rule List:" -ForegroundColor Yellow
    Write-Host "  ──────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    $counter = 1
    foreach ($rule in $Rules) {
        $statusColor = if ($rule.Enabled) { "Yellow" } else { "Red" }
        $statusText = if ($rule.Enabled) { "Enabled" } else { "Disabled" }
        
        Write-Host "  [$counter] " -NoNewline -ForegroundColor DarkCyan
        Write-Host $rule.OriginalName -ForegroundColor White
        Write-Host "      Status: " -NoNewline -ForegroundColor DarkGray
        Write-Host $statusText -ForegroundColor $statusColor
        Write-Host "      Reason: " -NoNewline -ForegroundColor DarkGray
        Write-Host $rule.DisableReason -ForegroundColor Yellow
        Write-Host "      Type:   " -NoNewline -ForegroundColor DarkGray
        Write-Host $rule.Kind -ForegroundColor Gray
        Write-Host ""
        $counter++
    }
    
    Write-Host "  ═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
}

function Repair-AutoDisabledRule {
    param(
        [PSCustomObject]$Rule,
        [string]$ResourceGroupName,
        [string]$WorkspaceName,
        [hashtable]$AuthHeader,
        [string]$SubscriptionId
    )
    
    try {
        $baseUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/"
        $uri = $baseUrl + "alertRules/$($Rule.RuleId)?api-version=2023-12-01-preview"
        
        # Clone the rule object to modify
        $updatedRule = $Rule.RuleObject | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        
        # Update display name
        $updatedRule.properties.displayName = $Rule.OriginalName
        
        # Restore original description
        if ($Rule.OriginalDescription) {
            $updatedRule.properties.description = $Rule.OriginalDescription
        }
        elseif ($updatedRule.properties.description) {
            $desc = $updatedRule.properties.description
            
            $failurePrefix = "The alert rule was disabled due to too many consecutive failures."
            $knownReasonStrings = @(
                "Reason: The query was blocked as it was consuming too many resources.",
                "Reason: The target table (on which the rule query operated) was deleted.",
                "Reason: Permissions to one of the data sources of the rule query were changed.",
                "Reason: Insufficient access to resource.",
                "Reason: A function used by the rule query is no longer valid.",
                "Reason: Microsoft Sentinel was removed from the target workspace.",
                "Reason: One of the data sources of the rule query were disconnected."
            )
            
            $cleanDescription = $desc
            $cleanDescription = $cleanDescription -replace [regex]::Escape($failurePrefix), ''
            
            foreach ($reasonStr in $knownReasonStrings) {
                $cleanDescription = $cleanDescription -replace [regex]::Escape($reasonStr), ''
            }
            
            $cleanDescription = $cleanDescription -replace '^\s*[\n\r]+', ''
            $cleanDescription = $cleanDescription.Trim()
            
            $updatedRule.properties.description = $cleanDescription
        }
        
        # Re-enable the rule
        $updatedRule.properties.enabled = $true
        
        # Remove read-only properties
        $updatedRule.properties.PSObject.Properties.Remove('lastModifiedUtc')
        $updatedRule.PSObject.Properties.Remove('etag')
        $updatedRule.PSObject.Properties.Remove('id')
        $updatedRule.PSObject.Properties.Remove('name')
        $updatedRule.PSObject.Properties.Remove('type')
        $updatedRule.PSObject.Properties.Remove('systemData')
        
        $body = $updatedRule | ConvertTo-Json -Depth 100
        
        # Update the rule via API
        $null = Invoke-RestMethod -Method "Put" -Uri $uri -Headers $AuthHeader -Body $body -ContentType "application/json"
        
        return $true
    }
    catch {
        Write-Host "      Error: $_" -ForegroundColor Red
        return $false
    }
}

function Start-RemediationWorkflow {
    param(
        [array]$Rules,
        [string]$ResourceGroupName,
        [string]$WorkspaceName,
        [hashtable]$AuthHeader,
        [string]$SubscriptionId
    )
    
    Write-Host "  Remediation Options:" -ForegroundColor Yellow
    Write-Host "  This will:" -ForegroundColor Gray
    Write-Host "    • Remove 'AUTO DISABLED' prefix from rule names" -ForegroundColor DarkGray
    Write-Host "    • Restore original descriptions (remove failure messages)" -ForegroundColor DarkGray
    Write-Host "    • Re-enable the rules" -ForegroundColor DarkGray
    Write-Host ""
    
    Write-Host "  [A] Remediate ALL rules ($($Rules.Count) rules)" -ForegroundColor Cyan
    Write-Host "  [S] Select specific rules to remediate" -ForegroundColor Cyan
    Write-Host "  [C] Cancel and exit" -ForegroundColor Cyan
    Write-Host ""
    
    $choice = Read-Host "  Enter your choice (A/S/C)"
    
    $rulesToRemediate = @()
    
    switch ($choice.ToUpper()) {
        'A' {
            $rulesToRemediate = $Rules
        }
        'S' {
            Write-Host ""
            Write-Host "  Enter rule numbers to remediate (comma-separated, e.g., 1,3,5)" -ForegroundColor Yellow
            Write-Host "  Or enter a range (e.g., 1-5)" -ForegroundColor Yellow
            Write-Host ""
            
            $selection = Read-Host "  Selection"
            
            if ([string]::IsNullOrWhiteSpace($selection)) {
                Show-Status "No rules selected. Remediation cancelled." -Type Warning
                return
            }
            
            # Parse selection
            $selectedIndices = @()
            $parts = $selection -split ','
            
            foreach ($part in $parts) {
                $part = $part.Trim()
                if ($part -match '^(\d+)-(\d+)$') {
                    # Range
                    $start = [int]$matches[1]
                    $end = [int]$matches[2]
                    for ($i = $start; $i -le $end; $i++) {
                        if ($i -ge 1 -and $i -le $Rules.Count) {
                            $selectedIndices += ($i - 1)  # Convert to 0-based
                        }
                    }
                }
                elseif ($part -match '^\d+$') {
                    $num = [int]$part
                    if ($num -ge 1 -and $num -le $Rules.Count) {
                        $selectedIndices += ($num - 1)  # Convert to 0-based
                    }
                }
            }
            
            $selectedIndices = $selectedIndices | Sort-Object -Unique
            
            if ($selectedIndices.Count -eq 0) {
                Show-Status "No valid rules selected. Remediation cancelled." -Type Warning
                return
            }
            
            foreach ($index in $selectedIndices) {
                $rulesToRemediate += $Rules[$index]
            }
            
            Write-Host ""
            Show-Status "Selected $($rulesToRemediate.Count) rule(s) for remediation" -Type Info
        }
        'C' {
            Show-Status "Remediation cancelled by user" -Type Warning
            return
        }
        default {
            Show-Status "Invalid choice. Remediation cancelled." -Type Warning
            return
        }
    }
    
    if ($rulesToRemediate.Count -eq 0) {
        Show-Status "No rules to remediate." -Type Warning
        return
    }
    
    Write-Host ""
    Write-Host "  Confirm remediation of $($rulesToRemediate.Count) rule(s)? (Y/N)" -ForegroundColor Yellow
    $confirm = Read-Host "  "
    
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Show-Status "Remediation cancelled by user" -Type Warning
        return
    }
    
    Write-Host ""
    Write-Host "  Starting remediation..." -ForegroundColor Cyan
    Write-Host ""
    
    $successCount = 0
    $failureCount = 0
    
    foreach ($rule in $rulesToRemediate) {
        Write-Host "  Remediating: " -NoNewline
        Write-Host $rule.OriginalName -NoNewline -ForegroundColor White
        Write-Host "..." -NoNewline
        
        $result = Repair-AutoDisabledRule -Rule $rule -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -AuthHeader $AuthHeader -SubscriptionId $SubscriptionId
        
        if ($result) {
            Write-Host " [SUCCESS]" -ForegroundColor Green
            $successCount++
        }
        else {
            Write-Host " [FAILED]" -ForegroundColor Red
            $failureCount++
        }
    }
    
    Write-Host ""
    Write-Host "  ═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "                      REMEDIATION SUMMARY                             " -ForegroundColor Cyan
    Write-Host "  ═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Total selected: $($rulesToRemediate.Count)" -ForegroundColor Gray
    Write-Host "  Successful:     $successCount" -ForegroundColor Green
    Write-Host "  Failed:         $failureCount" -ForegroundColor $(if ($failureCount -gt 0) { "Red" } else { "Gray" })
    Write-Host ""
    Write-Host "  ═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

function Start-AutoDisabledRuleRemediation {
    Clear-Host
    Show-Banner
    
    # Check and install required modules
    if (-not (Test-RequiredModules)) {
        Write-Host ""
        Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }
    
    Start-Sleep -Seconds 1
    
    # Step 1: Authentication
    if (-not (Connect-ToAzure)) {
        Write-Host ""
        Show-Status "Exiting due to authentication failure" -Type Error
        Write-Host ""
        Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }
    
    Start-Sleep -Seconds 1
    
    # Step 2: Select Subscription
    $subscription = Select-Subscription
    if (-not $subscription) {
        return
    }
    
    Clear-Host
    Show-Banner
    Show-Status "Selected subscription: $($subscription.Name)" -Type Success
    Write-Host ""
    Start-Sleep -Seconds 1
    
    # Step 3: Select Resource Group
    $resourceGroup = Select-ResourceGroup
    if (-not $resourceGroup) {
        return
    }
    
    Clear-Host
    Show-Banner
    Show-Status "Selected resource group: $resourceGroup" -Type Success
    Write-Host ""
    Start-Sleep -Seconds 1
    
    # Step 4: Select Workspace
    $workspace = Select-Workspace -ResourceGroupName $resourceGroup
    if (-not $workspace) {
        return
    }
    
    Clear-Host
    Show-Banner
    Show-Status "Selected workspace: $workspace" -Type Success
    Write-Host ""
    Start-Sleep -Seconds 1
    
    # Setup authentication header
    Clear-Host
    Show-Banner
    Show-Status "Setting up API authentication..." -Type Info
    
    $context = Get-AzContext
    $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    $profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
    $token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
    $authHeader = @{
        'Content-Type'  = 'application/json'
        'Authorization' = 'Bearer ' + $token.AccessToken
    }
    $subscriptionId = $context.Subscription.Id
    
    Write-Host ""
    
    # Get AUTO DISABLED rules
    $autoDisabledRules = Get-AutoDisabledRules -ResourceGroupName $resourceGroup -WorkspaceName $workspace -AuthHeader $authHeader -SubscriptionId $subscriptionId
    
    # Check if the result is an actual error ($null returned from catch block)
    # vs empty array (no auto-disabled rules found - function returns , @())
    # Using -is [array] to distinguish - an empty array is still an array
    if (-not ($autoDisabledRules -is [array])) {
        Write-Host ""
        Show-Status "Failed to retrieve analytics rules. Check permissions and try again." -Type Error
        Write-Host ""
        Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }
    
    if ($autoDisabledRules.Count -eq 0) {
        Write-Host ""
        Write-Host "  ═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host "                         SCAN COMPLETE                                " -ForegroundColor Green
        Write-Host "  ═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Workspace:    $workspace" -ForegroundColor Gray
        Write-Host "  Resource Grp: $resourceGroup" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Result: " -NoNewline -ForegroundColor Gray
        Write-Host "No AUTO DISABLED rules found" -ForegroundColor Green
        Write-Host ""
        Write-Host "  All analytics rules in this workspace are operating normally." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  ═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }
    
    Clear-Host
    Show-Banner
    
    # Show summary of AUTO DISABLED rules
    Show-AutoDisabledRulesSummary -Rules $autoDisabledRules
    
    # Start remediation workflow
    Start-RemediationWorkflow -Rules $autoDisabledRules -ResourceGroupName $resourceGroup -WorkspaceName $workspace -AuthHeader $authHeader -SubscriptionId $subscriptionId
    
    Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Run the tool
Start-AutoDisabledRuleRemediation
