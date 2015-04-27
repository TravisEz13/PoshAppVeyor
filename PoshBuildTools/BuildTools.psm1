[string] $moduleDir = Split-Path -Path $script:MyInvocation.MyCommand.Path -Parent

Set-StrictMode -Version latest
$webClient = New-Object 'System.Net.WebClient';
$repoName = ${env:APPVEYOR_REPO_NAME}
$branchName = $env:APPVEYOR_REPO_BRANCH
$pullRequestTitle = ${env:APPVEYOR_PULL_REQUEST_TITLE}

function Invoke-RunTest {
    param
    (
        [CmdletBinding()]
        [string]
        $Path, 
        
        [Object[]] 
        $CodeCoverage
    )
    Write-Info "Running tests: $Path"
    $testResultsFile = 'TestsResults.xml'
    
    $res = Invoke-Pester -OutputFormat NUnitXml -OutputFile $testResultsFile -PassThru @PSBoundParameters
    New-AppVeyorTestResult -testResultsFile $testResultsFile
    Write-Info 'Done running tests.'
    return $res
}

function New-AppVeyorTestResult
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true, Position=0, HelpMessage='Please add a help message here')]
        [Object]
        $testResultsFile
    )    

    Invoke-WebClientUpload -url "https://ci.appveyor.com/api/testresults/nunit/${env:APPVEYOR_JOB_ID}" -path $testResultsFile 
}
function Invoke-WebClientUpload
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true, Position=0)]
        [Object]
        $url,
        
        [Parameter(Mandatory=$true, Position=1)]
        [Object]
        $path
    )
    
    $webClient.UploadFile($url, (Resolve-Path $path))
}



function Write-Info {
     param
     (
         [Parameter(Mandatory=$true, Position=0)]
         [string]
         $message
     )

    Write-Host -ForegroundColor Yellow  "[APPVEYOR] [$([datetime]::UtcNow)] $message"
}

function Update-ModuleVersion
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]
        $modulePath,

        [Parameter(Mandatory=$true, Position=1)]
        [string]
        $moduleName,

        [ValidateNotNullOrEmpty()]
        [string]
        $version = $env:APPVEYOR_BUILD_VERSION
        )
    Write-Info "Updating Module version to: $version"

    $moduleInfo = Get-ModuleByPath -modulePath $modulePath -moduleName $moduleName
    if($moduleInfo)
    {
        $newVersion = ConvertTo-Version -version $version
        $FunctionsToExport = @()
        foreach($key in $moduleInfo.ExportedFunctions.Keys)
        {
            $FunctionsToExport += $key
        }
        $psd1Path = (Join-path $modulePath "${moduleName}.psd1")
        copy-item $psd1Path ".\${moduleName}Original.psd1.tmp"
        New-ModuleManifest -Path $psd1Path -Guid $moduleInfo.Guid -Author $moduleInfo.Author -CompanyName $moduleInfo.CompanyName `
            -Copyright $moduleInfo.Copyright -RootModule $moduleInfo.RootModule -ModuleVersion $newVersion -Description $moduleInfo.Description -FunctionsToExport $FunctionsToExport
    }
    else {
        throw "Couldn't load moduleInfo for $moduleName"
    }
}

function Get-ModuleByPath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$false, Position=0)]
        [string]
        $modulePath ,

        [Parameter(Mandatory=$false, Position=1)]
        [string]
        $moduleName
    )
    $modulePath = (Resolve-Path $modulePath).ProviderPath
    
    
    Write-Info "Getting module info for: $modulePath"
    
    $getParams = @{}
    if ($PSVersionTable.PSVersion.Major -ge 5)
    {
        $getParams.Add('listAvailable', $true)
    }
    
    Import-Module $modulePath -Force
    $moduleInfo = Get-Module -Name $moduleName @getParams
    return $moduleInfo
}



function ConvertTo-Version
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $version
    )
    
    
    $versionParts = $version.split('.')
    $newVersion = New-Object -TypeName 'System.Version' -ArgumentList @($versionParts[0],$versionParts[1],$versionParts[2],$versionParts[3])
    return $newVersion
}

function Update-Nuspec
{
    param(
        $modulePath,
        $moduleName,
        $version = ${env:APPVEYOR_BUILD_VERSION}
        )

    Write-Info "Updating nuspec: $version; $moduleName"
    $nuspecPath = (Join-path $modulePath "${moduleName}.nuspec")
    [xml]$xml = Get-Content -Raw $nuspecPath
    $xml.package.metadata.version = $version
    $xml.package.metadata.id = $ModuleName
    
    Update-NuspecXml -nuspecXml $xml -nuspecPath $nuspecPath
}

function New-BuildModuleInfo
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]
                        $ModuleName ,
        [Parameter(Mandatory=$true)]
        [string]
                        $ModulePath ,
                        [string[]] $CodeCoverage,
                        [string[]] $Tests = @('.\tests')
    )

    $moduleInfo = New-Object PSObject -Property @{
        ModuleName = $ModuleName
        ModulePath = $ModulePath
        CodeCoverage = $CodeCoverage
        Tests = $Tests
        }
    $moduleInfo.pstypenames.clear()
    $moduleInfo.pstypenames.add('PoshBuildTools.Build.ModuleInfo')
    return $moduleInfo
}
function Update-NuspecXml
{

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [xml]
        $nuspecXml,
        [Parameter(Mandatory=$true)]
        [string]
        $nuspecPath
    )
    
    $nuspecXml.OuterXml | out-file -FilePath $nuspecPath
}


function Install-NugetPackage
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$false)]
        [System.String]
        $source = 'https://www.powershellgallery.com/api/v2',
        
        [Parameter(Mandatory=$false)]
        [Object]
        $outputDirectory = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\",

        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $package
    )

    Write-Info "Installing $package using nuget"
    &nuget.exe install $package -source $source -outputDirectory $outputDirectory -ExcludeVersion
}