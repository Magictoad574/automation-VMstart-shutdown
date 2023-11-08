# Step 1: Preparing Azure Automation

# Connect to the Azure environment
# Change this if using in IL6
# This step is unnecessary if using Cloud Shell
Connect-AzAccount -Environment 'AzureUSGovernment'

# Variables (Replace these with your desired names and values)
$resourceGroupName = "rg-scanlan-sandbox"
$location = "usgovvirginia" # Use IL6 region names as applicable.
$automationAccountName = "aa-vmManagement"
$startRunbookName = "MorningStartVMs"
$stopRunbookName = "EveningStopVMs"
$subscriptionId = "subscription ID" # Replace with your actual subscription ID

# Create Automation Account
New-AzAutomationAccount -Name $automationAccountName -Location $location -ResourceGroupName $resourceGroupName

# Enable System Assigned Identity under Automation Account
Set-AzAutomationAccount -Name $automationAccountName -ResourceGroupName $resourceGroupName -AssignSystemIdentity #-AssignIdentity

# Get the identity object for the Automation Account
$automationIdentity = (Get-AzAutomationAccount -ResourceGroupName $resourceGroupName -Name $automationAccountName).Identity

#pause 10 seconds here (for System Identity to populate on back-end)
Start-Sleep -Seconds 10

# Grant that Identity Contributor role under RBAC
New-AzRoleAssignment -ObjectId $automationIdentity.PrincipalId -RoleDefinitionName "Contributor" -Scope "/subscriptions/$subscriptionId"




# Step 2: Create Tags under Subscription in Azure Portal

# Tags can be applied via Azure Policy, manually via Azure Portal GUI, or by script.
# Something like the following format (Tag Name : Tag Value)
#   AlwaysOn : True 
#   AlwaysOn : False



# Step 3: Create Runbooks

# Save the runbook content to a file in the current directory for starting VMs
$startRunbookFilePath = "./MorningStartVMs.ps1"
$startRunbookContent = @"
# Get a list of VMs to be started based on the tag
`$VMs = @(Get-AzResource -ResourceType "Microsoft.Compute/virtualmachines" -TagName "AlwaysOn" -TagValue "No")

# Start each VM in that list
foreach(`$VM in `$VMs) {
    Start-AzVM -ResourceGroupName `$VM.ResourceGroupName -Name `$VM.Name
}
"@
Set-Content -Path $startRunbookFilePath -Value $startRunbookContent

# Import the start runbook content
Import-AzAutomationRunbook -AutomationAccountName $automationAccountName -Name $startRunbookName -ResourceGroupName $resourceGroupName -Type 'PowerShell' -Path $startRunbookFilePath

# Publish the start runbook
Publish-AzAutomationRunbook -AutomationAccountName $automationAccountName -Name $startRunbookName -ResourceGroupName $resourceGroupName

# Optionally, remove the start runbook file after importing
Remove-Item -Path $startRunbookFilePath

# Save the runbook content to a file in the current directory for stopping VMs
$stopRunbookFilePath = "./EveningStopVMs.ps1"
$stopRunbookContent = @"
# Get a list of VMs to be stopped based on the tag
`$VMs = @(Get-AzResource -ResourceType "Microsoft.Compute/virtualmachines" -TagName "AlwaysOn" -TagValue "No")

# Stop each VM in that list
foreach(`$VM in `$VMs) {
    Stop-AzVM -ResourceGroupName `$VM.ResourceGroupName -Name `$VM.Name -Force
}
"@
Set-Content -Path $stopRunbookFilePath -Value $stopRunbookContent

# Import the stop runbook content
Import-AzAutomationRunbook -AutomationAccountName $automationAccountName -Name $stopRunbookName -ResourceGroupName $resourceGroupName -Type 'PowerShell' -Path $stopRunbookFilePath

# Publish the stop runbook
Publish-AzAutomationRunbook -AutomationAccountName $automationAccountName -Name $stopRunbookName -ResourceGroupName $resourceGroupName

# Optionally, remove the stop runbook file after importing
Remove-Item -Path $stopRunbookFilePath

# Calculate the next occurrence of 6:00 AM MST from the current time
$nextStartTime = (Get-Date).Date.AddHours(6)
if ($nextStartTime -lt (Get-Date).AddMinutes(5)) {
    $nextStartTime = $nextStartTime.AddDays(1)
}

# Create a schedule for the start runbook to run at the next 6:00 AM MST
$startScheduleName = "MorningStartVMsSchedule"
New-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $startScheduleName -StartTime $nextStartTime -DayInterval 1 -ResourceGroupName $resourceGroupName -TimeZone "Mountain Standard Time"

# Link the start runbook to its schedule
Register-AzAutomationScheduledRunbook -AutomationAccountName $automationAccountName -Name $startRunbookName -ScheduleName $startScheduleName -ResourceGroupName $resourceGroupName

# Calculate the next occurrence of 10:00 PM MST from the current time
$nextStopTime = (Get-Date).Date.AddHours(22)
if ($nextStopTime -lt (Get-Date).AddMinutes(5)) {
    $nextStopTime = $nextStopTime.AddDays(1)
}

# Create a schedule for the stop runbook to run at the next 10:00 PM MST
$stopScheduleName = "EveningStopVMsSchedule"
New-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $stopScheduleName -StartTime $nextStopTime -DayInterval 1 -ResourceGroupName $resourceGroupName -TimeZone "Mountain Standard Time"

# Link the stop runbook to its schedule
Register-AzAutomationScheduledRunbook -AutomationAccountName $automationAccountName -Name $stopRunbookName -ScheduleName $stopScheduleName -ResourceGroupName $resourceGroupName
