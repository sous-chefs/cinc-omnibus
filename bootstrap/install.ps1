#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$RepoBranch = if ($env:REPO_BRANCH) { $env:REPO_BRANCH } else { 'main' }
$ChefIngredientBranch = if ($env:CHEF_INGREDIENT_BRANCH) { $env:CHEF_INGREDIENT_BRANCH } else { 'main' }

$CincClient = 'C:\cinc-project\cinc\bin\cinc-client.bat'

if (-not (Test-Path $CincClient)) {
  . { Invoke-WebRequest -UseBasicParsing -Uri 'https://omnitruck.cinc.sh/install.ps1' } | Invoke-Expression
  install
}

$Work = 'C:\cinc'
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path "$Work\cookbooks", "$Work\cache" | Out-Null

Invoke-WebRequest -UseBasicParsing `
  -Uri "https://github.com/sous-chefs/cinc-omnibus/archive/refs/heads/$RepoBranch.zip" `
  -OutFile "$Work\cinc-omnibus.zip"
Invoke-WebRequest -UseBasicParsing `
  -Uri "https://github.com/sous-chefs/chef-ingredient/archive/refs/heads/$ChefIngredientBranch.zip" `
  -OutFile "$Work\chef-ingredient.zip"

Expand-Archive -Path "$Work\cinc-omnibus.zip" -DestinationPath $Work -Force
Expand-Archive -Path "$Work\chef-ingredient.zip" -DestinationPath $Work -Force

Move-Item "$Work\cinc-omnibus-$RepoBranch" "$Work\cookbooks\cinc-omnibus"
Move-Item "$Work\chef-ingredient-$ChefIngredientBranch" "$Work\cookbooks\chef-ingredient"
Copy-Item -Recurse "$Work\cookbooks\cinc-omnibus\bootstrap\cookbooks\cinc-omnibus-bootstrap" "$Work\cookbooks\"
Copy-Item "$Work\cookbooks\cinc-omnibus\bootstrap\client.windows.rb" "$Work\client.rb"
Copy-Item "$Work\cookbooks\cinc-omnibus\bootstrap\runlist\builder.json" "$Work\dna.json"

& $CincClient `
  --local-mode `
  --config "$Work\client.rb" `
  --log_level auto `
  --force-formatter `
  --no-color `
  --json-attributes "$Work\dna.json" `
  --chef-zero-port 8889

# Uninstall cinc-client via the MSI's recorded UninstallString and wipe
# the scratch dir. The toolchain itself was installed by the converge
# above and lives at C:\cinc-project\omnibus-toolchain — untouched here.
$cinc = Get-ChildItem 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' |
  ForEach-Object { Get-ItemProperty $_.PSPath } |
  Where-Object { $_.DisplayName -like 'Cinc Client*' } |
  Select-Object -First 1
if ($cinc) {
  Start-Process msiexec.exe -ArgumentList "/x $($cinc.PSChildName) /quiet /norestart" -Wait
}

Remove-Item -Recurse -Force $Work
