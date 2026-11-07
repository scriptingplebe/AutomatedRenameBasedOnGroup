using namespace System.Net
using namespace System.Security.Cryptography.X509Certificates

param($Request, $TriggerMetadata)

# Grab cert from header
$base64Cert = $request.Headers["X-ARR-ClientCert"]

try {
# Convert the Base64 string into a raw byte array
$certBytes = [Convert]::FromBase64String($base64Cert)

# Create a new cert
$SCEPcert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)

$rootThumbprint = # Your Enviormental Variable
$issuerThumbprint = # Your Enviormental Variable

$rootCert = Get-Item "Cert:\CurrentUser\My\# Your Enviormental Variable"
$issuerCert = Get-Item "Cert:\CurrentUser\My\# Your Enviormental Variable"

# Create a new X509 chain for validation
$chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()

$chain.ChainPolicy.TrustMode = [System.Security.Cryptography.X509Certificates.X509ChainTrustMode]::CustomRootTrust

$chain.ChainPolicy.CustomTrustStore.Add($rootCert)

$chain.ChainPolicy.ExtraStore.Add($issuerCert)

$chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck

$isValid = $chain.Build($SCEPcert)  

if (-not $isValid) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Forbidden
        Headers = @{
            "Content-Type" = "application/json"
        }
        Body = @{
            Success = $false
            Error   = "Certificate validation failed."
        } | ConvertTo-Json -Compress
    })

    return
}

$Body = $Request.Body

$TargetDeviceId = $Body.DeviceId

$SerialNumber = $Body.SerialNumber

    try {
        # Connect silently to Graph using the Function's System-Assigned Managed Identity
        Connect-MgGraph -Identity -NoWelcome
    
        # Find the corresponding Graph device object
        $deviceObject = Get-MgDevice -Filter "deviceId eq '$TargetDeviceId'"
 
        # Get needed group information for the device and create a variable based on the group name
        $groups = Get-MgDeviceMemberOf -DeviceId $deviceObject.Id -All
 
        # Grabs the group name from the device object and creates a new variable based on the group name
        $GroupName = $groups | ForEach-Object { $_.AdditionalProperties.displayName} | Where-Object { $_ -like '# Your Group Name'} | Select-Object -First 1
 
        # Removes any characters after the 6th character in the group name to create a new variable
        $NewGroupName = $GroupName.substring(0,6)

        # Combine the group name and serial number to create a new device name
        $NewComputerName = "# Your Computer Name-$SerialNumber"

        # Updates the group tag in Autopilot to show that the device has been deployed
        $AutoPilot = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber, '$SerialNumber')"

        $AutoPilotId = $AutoPilot.Id

        Update-MgDeviceManagementWindowsAutopilotDeviceIdentityDeviceProperty -WindowsAutopilotDeviceIdentityId $AutoPilotId -Grouptag "# Your Group Tag"

            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
                Body       = @{ 
                TargetName = # Your Computer Name
                } | ConvertTo-Json
            })
        } catch {
        # Catch backend API, token, or query issues and send them cleanly to the client for tracking
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Error = $_.Exception.Message } | ConvertTo-Json
            })
        }
} catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Headers = @{
            "Content-Type" = "application/json"
        }
        Body = @{
            Success = $false
            Error   = $_.Exception.Message
        } | ConvertTo-Json -Compress
    })
}
