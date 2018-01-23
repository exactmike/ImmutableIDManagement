function TestIsWriteableDirectory
    {
        #Credits to the following:
        #http://poshcode.org/2236
        #http://stackoverflow.com/questions/9735449/how-to-verify-whether-the-share-has-write-access
        #pulled in from OneShell module: https://github.com/exactmike/OneShell
        [CmdletBinding()]
        param
        (
            [parameter()]
            [ValidateScript(
                {
                    $IsContainer = Test-Path -Path ($_) -PathType Container
                    if ($IsContainer)
                    {
                        $Item = Get-Item -Path $_
                        if ($item.PsProvider.Name -eq 'FileSystem') {$true}
                        else {$false}
                    }
                    else {$false}
                }
            )]
            [string]$Path
        )
        try
        {
            $testPath = Join-Path -Path $Path -ChildPath ([IO.Path]::GetRandomFileName())
                New-Item -Path $testPath -ItemType File -ErrorAction Stop > $null
            $true
        }
        catch
        {
            $false
        }
        finally
        {
            Remove-Item -Path $testPath -ErrorAction SilentlyContinue
        }
    }
#end function TestIsWriteableDirectory
Function WriteLog
    {
        [cmdletbinding()]
        Param
        (
            [Parameter(Mandatory,Position=0)]
            [ValidateNotNullOrEmpty()]
            [string]$Message
            ,
            [Parameter(Position=1)]
            [string]$LogPath
            ,
            [Parameter(Position=2)]
            [switch]$ErrorLog
            ,
            [Parameter(Position=3)]
            [string]$ErrorLogPath
            ,
            [Parameter(Position=4)]
            [ValidateSet('Attempting','Succeeded','Failed','Notification')]
            [string]$EntryType
        )
        GetCallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -Name VerbosePreference
        $TimeStamp = Get-Date -Format yyyyMMdd-HHmmss
        #Add the Entry Type to the message or add nothing to the message if there is not EntryType specified - preserves legacy functionality and adds new EntryType capability
        if (-not [string]::IsNullOrWhiteSpace($EntryType)) {$Message = $EntryType + ':' + $Message}
        $Message = $TimeStamp + ' ' + $Message
        #check the Log Preference to see if the message should be logged or not
        if ($null -eq $LogPreference -or $LogPreference -eq $true)
        {
            #Set the LogPath and ErrorLogPath to the parent scope values if they were not specified in parameter input.  This allows either global or parent scopes to set the path if not set locally
            if ([string]::IsNullOrWhiteSpace($Local:LogPath))
            {
                if (-not [string]::IsNullOrWhiteSpace($Script:LogPath))
                {
                    $Local:LogPath = $script:LogPath
                }
            }
            #Write to Log file if LogPreference is not $false and LogPath has been provided
            if (-not [string]::IsNullOrWhiteSpace($Local:LogPath))
            {
                $Message | Out-File -FilePath $Local:LogPath -Append
            }
            else
            {
                Write-Error -Message 'No LogPath has been provided. Writing Log Entry to script module variable UnwrittenLogEntries' -ErrorAction SilentlyContinue
                if (Test-Path -Path variable:script:UnwrittenLogEntries)
                {
                    $Script:UnwrittenLogEntries += $Message
                }
                else
                {
                    $Script:UnwrittenLogEntries = @()
                    $Script:UnwrittenLogEntries += $Message
                }
            }
            #if ErrorLog switch is present also write log to Error Log
            if ($ErrorLog) {
                if ([string]::IsNullOrWhiteSpace($Local:ErrorLogPath))
                {
                    if (-not [string]::IsNullOrWhiteSpace($Script:ErrorLogPath))
                    {
                        $Local:ErrorLogPath = $Script:ErrorLogPath
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace($Local:ErrorLogPath))
                {
                    $Message | Out-File -FilePath $Local:ErrorLogPath -Append
                }
                else
                {
                    if (Test-Path -Path variable:script:UnwrittenErrorLogEntries)
                    {
                        $Script:UnwrittenErrorLogEntries += $Message 
                    }
                    else
                    {
                        $Script:UnwrittenErrorLogEntries = @()
                        $Script:UnwrittenErrorLogEntries += $Message
                    }
                }
            }
        }
        #Pass on the message to Write-Verbose if -Verbose was detected
        Write-Verbose -Message $Message
    }
#end Function WriteLog
function GetAdObjectDomain
    {
        [cmdletbinding(DefaultParameterSetName='ADObject')]
        param(
        [parameter(Mandatory,ParameterSetName='ADObject')]
        [ValidateScript({Test-Member -InputObject $_ -Name CanonicalName})]
        $adobject
        ,
        [parameter(Mandatory,ParameterSetName='ExchangeObject')]
        [ValidateScript({Test-Member -InputObject $_ -Name Identity})]
        $ExchangeObject
        )
        switch ($PSCmdlet.ParameterSetName)
        {
            'ADObject'
            {[string]$domain=$adobject.canonicalname.split('/')[0]}
            'ExchangeObject'
            {[string]$domain=$ExchangeObject.Identity.split('/')[0]}
        }
        $domain
    }
# end function GetADObjectDomain
function GetDomainFQDNFromAnyDN
    {
        [CmdletBinding()]
        param
        (
            [parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]
            [string[]]$DistinguishedName
        )
        process
        {
            foreach ($dn in $DistinguishedName)
            {
                $StartDomainIndex = $dn.IndexOf('DC=')
                $DomainString = $dn.Substring($StartDomainIndex)
                $FQDN = $DomainString.Replace('DC=','').Replace(',','.')
                $FQDN
            }
        }
    }
#end function GetDomainFQDNFromAnyDN