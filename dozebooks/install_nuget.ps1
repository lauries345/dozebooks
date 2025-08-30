# Create a tools folder
$tools = "$env:LOCALAPPDATA\Tools\NuGet"
New-Item -ItemType Directory -Force -Path $tools | Out-Null

# Download the official nuget.exe
Invoke-WebRequest https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -OutFile "$tools\nuget.exe"

# Add to PATH for future shells
setx PATH "$env:PATH;$tools"

# Make it available in THIS shell too
$env:PATH += ";$tools"

# Sanity check
nuget.exe help
