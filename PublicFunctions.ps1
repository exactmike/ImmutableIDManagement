function Set-AttributeValue
    {
        <#
        .SYNOPSIS
        Sets a specified target attribute with the value from a specified source attribute for the specified object(s).
        
        .DESCRIPTION
        Copies a value from a source attribute to a target attribute for specified objects (via -Identity parameter), an entire AD domain subtree, an entire domain, or an entire forest.  Can ignore objects that already have a value in the target attribute. When processing a subtree, domain, or forest the function processes AD objects which are in objectcategory person or group. Requires you to have already created a connection to Active Directory Windows PowerShell ActiveDirectory module and to set the location of the PowerShell session to the Active Directory Provider PSDrive which you want the function to use.
       
        .EXAMPLE
        Set-Location AD:\
        Set-IIDAttributeValue -SearchScope SubTree -SearchBase 'OU=Users,OU=Managed,DC=corporate,DC=contoso,DC=com' -OnlyReport -ExportResults -OnlyUpdateNull -OutputFolderPath C:\SharedData\ImmutableIDResults -WriteLog
        
        .EXAMPLE
        Set-Location AD:\
        Set-IIDAttributeValue -DomainFQDN corporate.contoso.com -ExportResults -OnlyUpdateNull -OutputFolderPath C:\ImmutableIDResults -WriteLog -Verbose

        .EXAMPLE
        Set-Location AD:\
        Set-IIDAttributeValue -Identity 56b43a27-b029-40f4-b451-709185855d4b -OutputFolderPath C:\SharedData\ImmutableIDResults -Verbose -WhatIf
        
        .Notes
        Requires you to have already created a PSDrive connection to Active Directory with the Windows PowerShell ActiveDirectory module and to set the location of the PowerShell session to the Active Directory Provider PSDrive which you want the function to use.
        
        #>
        [cmdletbinding(DefaultParameterSetName='Identity',SupportsShouldProcess=$true)]
        param
        (
            # To set the immutable ID on all applicable objects in a forest, specify the forest fqdn
            [parameter(ParameterSetName = 'EntireForest',Mandatory)]
            [string]$ForestFQDN
            ,
            # When using SearchBase you may also set the Search Scope to Base, OneLevel, or SubTree.  Default is SubTree.
            [parameter(ParameterSetName = 'SearchBase')]
            [ValidateSet('Base','OneLevel','SubTree')]
            [string]$SearchScope = 'SubTree'
            ,
            # To set the immutable ID on all objects in a SearchBase, specify the SearchBase DistinguishedName.
            [parameter(ParameterSetName = 'SearchBase',Mandatory)]
            #[ValidateScript({Test-Path $_})] #need something more sophisticated to test this path
            [string]$SearchBase
            ,
            # To set the immutable ID on all applicable objects in a forest, specify the forest fqdn
            [parameter(ParameterSetName = 'EntireDomain',Mandatory)]
            [string]$DomainFQDN
            ,
            # To set the immutable ID on specified identified objects in a forest, specify the objects by DistinguishedName, ObjectGUID, or SAMAccountName
            [parameter(ParameterSetName = 'Identity',ValueFromPipelineByPropertyName = $true,Mandatory)]
            [Alias('DistinguishedName','SamAccountName','ObjectGUID')]
            [string[]]$Identity
            ,
            # Set the Attribute to be used as the ImmutableID Source to Set with this function.  Default is mS-DS-ConsistencyGuid
            [string]$ImmutableIDAttribute = 'mS-DS-ConsistencyGuid'
            ,
            # Set the Attribute to be used as the source of the value with which to set the ImmutableID source attribute. Default is ObjectGUID
            [string]$ImmutableIDAttributeSource = 'ObjectGUID'
            ,
            # Don't modify any objects, only report those that were identified to update. If OutputFolderPath was specified a csv report is produced, otherwise the report data objects are output to the pipeline.
            [switch]$OnlyReport
            ,
            # Export CSV files to the OutputFolderPath with the success and failure results
            [switch]$ExportResults
            ,
            # Write Operational and Error Logs to the OutputFolderPath
            [switch]$WriteLog
            ,
            # Update only the AD Objects found where the specified Immutable ID attribute is currently NULL.  
            [switch]$OnlyUpdateNull
            ,
            # Specify the output folder/directory for the function to use for log an csv output files. The location must already exist and be writeable.  Output files are date stamped and therefore in most cases should not conflict with any existing files. 
            [Parameter()]
            [ValidateScript({TestIsWriteableDirectory -Path $_})]
            [String]$OutputFolderPath
        )#end param
        Begin
        {
            $TimeStamp = Get-Date -Format yyyyMMdd-HHmmss
            if ($WriteLog -eq $true -or $ExportResults -eq $true)
            {
                if ($null -eq $OutputFolderPath)
                {
                    throw('You must specify the OutputFolderPath parameter when using the WriteLogs or ExportResults paramters.')
                }
            }
            if ($WriteLog -eq $true)
            {
                $script:LogPreference = $true
                $script:LogPath = Join-Path -path $OutputFolderPath -ChildPath $($TimeStamp + 'SetImmutableIDAttributeValueOperations.log')
                $script:ErrorLogPath = Join-Path -path $OutputFolderPath -ChildPath $($TimeStamp + 'SetImmutableIDAttributeValueOperations-ERRORS.log')    
            }
            else
            {
                $script:LogPreference = $false
            }
            WriteLog -Message "Command Line: $($MyInvocation.line)" -EntryType Notification
            #Check Current PSDrive Location: Should be AD, Should be Root of the PSDrive
            Set-Location -Path \
            $Location = Get-Location
            $PSDriveTests = @{
                ProviderIsActiveDirectory = $($Location.Provider.ToString() -like '*ActiveDirectory*')
                LocationIsRootOfDrive = ($Location.Path.ToString() -eq $($Location.Drive.ToString() + ':\'))
                ProviderPathIsRootDSE = ($Location.ProviderPath.ToString() -eq '//RootDSE/')
            }# End PSDriveTests
            if ($PSDriveTests.Values -contains $false)
            {
                WriteLog -ErrorLog -Verbose -Message "Set-ImmutableIDAttributeValue may not continue for the following reason(s) related to the command prompt location:"
                WriteLog -ErrorLog -Verbose -Message $($PSDriveTests.GetEnumerator() | Where-Object -filter {$_.Value -eq $False} | Select-Object @{n='TestName';e={$_.Key}},Value | ConvertTo-Json -Compress)
                Write-Error -Message "Set-ImmutableIDAttributeValue may not continue due to the command prompt location.  Review Error Log for details." -ErrorAction Stop
            }# End If
            #Setup operational parameters for Get-ADObject based on Parameter Set
            $GetADObjectParams = @{
                Properties = @('CanonicalName',$ImmutableIDAttributeSource,$ImmutableIDAttribute)
                ErrorAction = 'Stop'
            }# End GetADObjectParams
            switch ($PSCmdlet.ParameterSetName)
            {
                'EntireForest'
                {
                    Try
                    {
                        $GetADObjectParams.Filter = {objectCategory -eq 'Person' -or objectCategory -eq 'Group'}
                        $GetADObjectParams.ResultSetSize = $null
                        $message = "Find AD Forest $ForestFQDN"
                        WriteLog -Message $message -EntryType Attempting
                        $Forest = Get-ADForest -Identity $ForestFQDN -Server $ForestFQDN -ErrorAction Stop
                        $ForestDomains = @(
                            foreach ($d in $Forest.Domains)
                            {
                                Get-ADDomain -Identity $d -Server $d -ErrorAction Stop
                            }
                        )
                        $message = $message + "with domains $($forest.Domains -join ', ')"
                        WriteLog -Message $message -EntryType Succeeded
                    }
                    catch
                    {
                        WriteLog -Message $message -EntryType Failed -ErrorLog -Verbose
                        throw "Failed to get AD Forest $ForestFQDN"
                    }
                }# End EntireForest
                'EntireDomain'
                {
                    Try
                    {
                        $GetADObjectParams.Filter = {objectCategory -eq 'Person' -or objectCategory -eq 'Group'}
                        $GetADObjectParams.ResultSetSize = $null
                        $message = "Find AD Domain $DomainFQDN"
                        WriteLog -Message $message -EntryType Attempting
                        $Domain = Get-ADDomain -Identity $DomainFQDN -server $DomainFQDN -ErrorAction Stop
                        WriteLog -Message $message -EntryType Succeeded
                        $GetADObjectParams.Server = $Domain.DNSRoot
                    }
                    catch
                    {
                        WriteLog -Message $message -EntryType Failed -ErrorLog -Verbose
                        throw "Failed to get AD Domain $DomainFQDN"
                    }
                }# End EntireDomain
                'Identity'
                {
                    if ($ExportResults)
                    {
                        $ADObjectGetSuccesses = @()
                        $ADObjectGetFailures = @()
                    }
                    #$GetADObjectParams.ResultSetSize = 1
                }# End Single
                'SearchBase'
                {
                    $GetADObjectParams.Filter = {objectCategory -eq 'Person' -or objectCategory -eq 'Group'}
                    $GetADObjectParams.ResultSetSize = $null
                    $GetADObjectParams.SearchBase = $SearchBase
                    $GetADObjectParams.SearchScope = $SearchScope
                    $GetADObjectParams.Server = GetDomainFQDNFromAnyDN -DistinguishedName $SearchBase
                }# End SearchBase
            }# End Switch
            #Setup Export Files if $ExportResults is $true
            if ($ExportResults)
            {
                $OutputFileName = "SetImmutableIDAttributeValueResults.csv"
                $OutputFilePath = Join-Path -Path $OutputFolderPath -ChildPath $($TimeStamp + $OutputFileName)
            }
            # End if
        }
        # End Begin
        Process
        {
            $message = $PSCmdlet.MyInvocation.InvocationName + ': Get AD Objects with the Get-ADObject cmdlet.'
            WriteLog -Message $message -EntryType Attempting
            #region GetObjectToModify
            $ADObjects = @(
                switch ($PSCmdlet.ParameterSetName)
                {
                    'Identity'
                    {
                        foreach ($id in $Identity)
                        {
                            Try
                            {
                                $GetADObjectParams.Filter = "SAMAccountName -eq '$id' -or DistinguishedName -eq '$id' -or ObjectGUID -eq '$id'"
                                #$GetADObjectParams.Identity = $id
                                #Get the object first in order to get/verify the object's domain
                                $TempADObject = Get-ADObject @GetADObjectParams | Select-Object -ExcludeProperty Item,Property* -Property *,@{n='Domain';e={GetAdObjectDomain -adobject $_ -ErrorAction Stop}}
                                $GetADObjectParams.Server = $TempADObject.Domain
                                #Get the object from the domain so that we can get any attribute (some atttributes are not in the PAS - Partial Attribute Set - on global catalogs)
                                Get-ADObject @GetADObjectParams | Select-Object -ExcludeProperty Item,Property* -Property *,@{n='Domain';e={GetAdObjectDomain -adobject $_ -ErrorAction Stop}}
                                $ADObjectGetSuccesses += $id | Select-Object @{n='Identity';e={$id}},@{n='TimeStamp';e={$TimeStamp}},@{n='Status';e={'GetSucceeded'}},@{n='ErrorString';e={'N/A'}}
                                WriteLog -Message $message -Verbose -EntryType Succeeded
                            }# End Try
                            catch
                            {
                                WriteLog -Message $message -Verbose -EntryType Failed
                                WriteLog -Message $_.tostring() -ErrorLog
                                $ADObjectGetFailures += $id | Select-Object @{n='Identity';e={$id}},@{n='TimeStamp';e={$TimeStamp}},@{n='Status';e={'GetFailed'}},@{n='ErrorString';e={$_.tostring()}}
                            }# End Catch
                        } #end foreach id in identity
                        if ($ExportResults -and $ADObjectGetSuccesses.count -ge 1 -or $ADObjectGetFailures.count -ge 1)
                        {
                            $GetSuccessesFailuresFileName = $TimeStamp + 'ImmutableIDGetObjectFromIdentityResults.csv'
                            $GetSuccessesFailuresFilePath = Join-Path -Path $OutputFolderPath -ChildPath $GetSuccessesFailuresFileName
                            $($ADObjectGetSuccesses;$ADObjectGetFailures) | Export-Csv -Path $GetSuccessesFailuresFilePath -Encoding UTF8 -NoTypeInformation
                        }
                    }# End Single
                    'SearchBase'
                    {
                        Get-ADObject @GetADObjectParams | Select-Object -ExcludeProperty Item,Property* -Property *,@{n='Domain';e={$Domain.DNSRoot}}
                    }# End SearchBase
                    'EntireDomain'
                    {
                        WriteLog -Message "Get Objects from domain $($Domain.dnsroot)" -EntryType Notification
                        Get-ADObject @GetADObjectParams | Select-Object -ExcludeProperty Item,Property* -Property *,@{n='Domain';e={$Domain.DNSroot}}
                    }# End EntireForest
                    'EntireForest'
                    {
                        foreach ($d in $ForestDomains)
                        {
                            WriteLog -Message "Get Objects from domain $($d.DNSRoot)" -EntryType Notification
                            $GetADObjectParams.Server = $d.DNSRoot
                            Get-ADObject @GetADObjectParams | Select-Object -ExcludeProperty Item,Property* -Property *,@{n='Domain';e={$d.DNSRoot}}
                        }
                    }# End EntireForest
                } # end switch ParameterSetName
            )
            $message = $PSCmdlet.MyInvocation.InvocationName + ": Get $($ADObjects.Count) AD Objects with the Get-ADObject cmdlet."
            WriteLog -Message $message -EntryType Notification
            if ($OnlyUpdateNull -eq $true)
            {
                WriteLog -Message "Found $($ADObjects.count) AD Objects to test for NULL ImmutableIDAttribute $immutableIDAttribute" -EntryType Notification
                $ADObjects = @($ADObjects | Where-Object -FilterScript {$null -eq $_.$($ImmutableIDAttribute)})
            }#end If
            if ($OnlyReport -eq $true)
            {
                WriteLog -Message "Found $($adobjects.count) AD Objects that do not have a value in ImmutableIDAttribute $immutableIDAttribute" -EntryType Notification
                $attributeset = @('ObjectGUID','Domain','ObjectClass','DistinguishedName',@{n='TimeStamp';e={$TimeStamp}},@{n='Status';e={'ReportOnly-NoUpdatesPerformed'}},@{n='ErrorString';e={'None'}},@{n='SourceAttribute';e={$ImmutableIDAttributeSource}},@{n='TargetAttribute';e={$ImmutableIDAttribute}})
                if ($null -eq $OutputFolderPath)
                {
                    $ADObjects | Select-Object -Property $attributeset
                }
                elseif ($ExportResults -eq $true)
                {
                    if ($ImmutableIDAttributeSource -notin $attributeset) {$attributeset += $ImmutableIDAttributeSource}
                    if ($ImmutableIDAttribute -notin $attributeset) {$attributeset += $ImmutableIDAttribute}
                    $ADObjects | Select-Object -Property $attributeset | Export-Csv -Path $OutputFilePath -Encoding UTF8 -NoTypeInformation
                }

            }#end if
            else #Actually process (if -whatif was not used)
            {
                #Modify the objects that need modifying
                $O = 0 #Current Object Counter
                $ObjectCount = $ADObjects.Count
                $AllResults = @(
                    $ADObjects | ForEach-Object {
                        $CurrentObject = $_
                        $O++ #Current Object Counter Incremented
                        $LogString = "Set-ImmutableIDAttributeValue: Set Immutable ID Attribute $ImmutableIDAttribute for Object $($CurrentObject.ObjectGUID.tostring()) with the Set-ADObject cmdlet."
                        Write-Progress -Activity "Setting Immutable ID Attribute for $ObjectCount AD Object(s)" -PercentComplete $($O/$ObjectCount*100) -CurrentOperation $LogString
                        Try
                        {
                            if ($PSCmdlet.ShouldProcess($CurrentObject.ObjectGUID,"Set-ADObject $ImmutableIDAttribute with value $ImmutableIDAttributeSource"))
                            {
                                WriteLog -Message $LogString -EntryType Attempting
                                Set-ADObject -Identity $CurrentObject.ObjectGUID -Add @{$ImmutableIDAttribute=$($CurrentObject.$($ImmutableIDAttributeSource))} -Server $CurrentObject.Domain -ErrorAction Stop -confirm:$false #-WhatIf
                                WriteLog -Message $LogString -EntryType Succeeded
                                if ($ExportResults)
                                {
                                    $attributeset = @('ObjectGUID','Domain','ObjectClass','DistinguishedName',@{n='TimeStamp';e={Get-Date -Format yyyyMMdd-HHmmss}},@{n='Status';e={'Succeeded'}},@{n='ErrorString';e={'None'}},@{n='SourceAttribute';e={$ImmutableIDAttributeSource}},@{n='TargetAttribute';e={$ImmutableIDAttribute}})
                                    if ($ImmutableIDAttributeSource -notin $attributeset) {$attributeset += $ImmutableIDAttributeSource}
                                    if ($ImmutableIDAttribute -notin $attributeset) {$attributeset += $ImmutableIDAttribute}
                                    $CurrentObject | Select-Object -Property $attributeset
                                }# End if
                            }# End if
                        }# End try
                        Catch
                        {
                            $myerror = $_
                            WriteLog -Message $LogString -EntryType Failed -ErrorLog -Verbose
                            WriteLog -Message $myerror.ToString() -ErrorLog
                            if ($ExportResults)
                            {
                                $attributeset = @('ObjectGUID','Domain','ObjectClass','DistinguishedName',@{n='TimeStamp';e={Get-Date -Format yyyyMMdd-HHmmss}},@{n='Status';e={'Failed'}},@{n='ErrorString';e={$myerror.ToString()}},@{n='SourceAttribute';e={$ImmutableIDAttributeSource}},@{n='TargetAttribute';e={$ImmutableIDAttribute}})
                                if ($ImmutableIDAttributeSource -notin $attributeset) {$attributeset += $ImmutableIDAttributeSource}
                                if ($ImmutableIDAttribute -notin $attributeset) {$attributeset += $ImmutableIDAttribute}
                                $CurrentObject | Select-Object -Property $attributeset
                            }# End if
                        }# End Catch
                    }# End ForEach-Object
                )# end AllResults
                Write-Progress -Activity "Setting Immutable ID Attribute for $ObjectCount AD Object(s)" -Completed
            }#end else
        }
        End
        {
            if (-not $OnlyReport)
            {
                If ($ExportResults)
                {
                    $FailuresCount = $AllResults.Where({$_.Status -eq 'Failed'}).count
                    $SuccessesCount = $AllResults.Where({$_.Status -eq 'Succeeded'}).count
                    Export-Csv -InputObject $AllResults -Encoding UTF8 -Path $OutputFilePath -NoTypeInformation
                }
                WriteLog -message "Set-ImmutableIDAttributeValue Set AD Object Results: Total Attempts: $($AllResults.Count); Successes: $SuccessesCount; Failures: $FailuresCount."
                WriteLog -Message "Set-ImmutableIDAttributeValue Operations Completed."
            }
        }
    }
#end function Set-AttributeValue
