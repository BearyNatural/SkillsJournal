# Test:
Install-Module -Name AWSPowerShell -AllowClobber -Scope CurrentUser
cd container
# Confirm the IPs in the listofips.txt is correct
.\getips.ps1

# Start stress on 2 CPU cores
.\startStress.ps1

# Stop the stress
.\stopStress.ps1