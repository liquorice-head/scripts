# Define audit categories and their corresponding event IDs
$auditCategories = @{
    "AuditPolicyChange" = @("4713", "4716", "4719", "4867");
    "AuditComputerAccountManagement" = @("4741", "4742");
    "AuditDPAPIActivity" = @("4692");
    "AuditProcessCreation" = @("4688");
    "AuditSecurityGroupManagement" = @("4728", "4732", "4756");
    "AuditSystemExtension" = @("4610", "4697");
    "AuditSensitivePrivilegeUse" = @("4672", "4673", "4674");
    "AuditSpecialLogon" = @("4964");
    "AuditUserAccountManagement" = @("4720", "4722", "4723", "4724", "4725", "4726", "4738", "4740", "4767", "4780", "4781", "4782");
}

# Configure audit for each category and event ID
foreach ($category in $auditCategories.Keys) {
    foreach ($eventId in $auditCategories[$category]) {
        $command = "auditpol /set /subcategory:`"$category`" /success:enable /failure:disable"
        Invoke-Expression $command
        Write-Host "Audit policy configured for category $category (Event ID: $eventId)"
    }
}

# Verify audit configuration
Write-Host "Current audit configuration:"
Invoke-Expression "auditpol /get /category:*"
