function Set-AttributeValue
    {
        [cmdletbinding(DefaultParameterSetName='Single',SupportsShouldProcess=$true)]
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
            [ValidateScript({Test-Path $_})]
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
            # Don't modify any objects, only report those that were identified to update. 
            [switch]$OnlyReport
            ,
            # Export CSV files with the success and failure results
            [bool]$ExportResults = $true
            ,
            # Update only the AD Objects found where the specified Immutable ID attribute is currently NULL.  
            [switch]$OnlyUpdateNull
            ,
            # Specify the output folder/directory for the function to use for log an csv output files. The location must already exist and be writeable.  Output files are date stamped and therefore in most cases should not conflict with any existing files. 
            [Parameter(Mandatory)]
            [ValidateScript({TestIsWriteableDirectory -Path $_})]
            [String]$OutputFolderPath
        )#end param
        Begin
        {
            $TimeStamp = Get-Date -Format yyyyMMdd-HHmmss
            $script:LogPath = Join-Path -path $OutputFolderPath -ChildPath $($TimeStamp + 'SetImmutableIDAttributeValueOperations.log')
            $script:ErrorLogPath = Join-Path -path $OutputFolderPath -ChildPath $($TimeStamp + 'SetImmutableIDAttributeValueOperations-ERRORS.log')
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
                    }
                    catch
                    {
                        WriteLog -Message $message -EntryType Failed -ErrorLog -Verbose
                        throw "Failed to get AD Domain $DomainFQDN"
                    }
                }# End EntireForest
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
            WriteLog -Message $message -Verbose -EntryType Attempting
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
                                $GetADObjectParams.Identity = $id
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
                        #convert dn to a domain fqdn to use for -server param

                        Get-ADObject @GetADObjectParams | Select-Object -ExcludeProperty Item,Property* -Property *,@{n='Domain';e={$Domain.DNSRoot}}
                    }# End SearchBase
                    'EntireDomain'
                    {
                        WriteLog -Message "Get Objects from domain $($Domain.dnsroot)" -EntryType Notification
                        $GetADObjectParams.Server = $Domain.dnsroot
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
                if ($ImmutableIDAttributeSource -notin $attributeset) {$attributeset += $ImmutableIDAttributeSource}
                if ($ImmutableIDAttribute -notin $attributeset) {$attributeset += $ImmutableIDAttribute}
                $ADObjects | Select-Object -Property $attributeset | Export-Csv -Path $OutputFilePath -Encoding UTF8 -NoTypeInformation
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
                    Export-Data -DataToExportTitle $ExportName -DataToExport $AllResults -DataType csv
                }
                WriteLog -message "Set-ImmutableIDAttributeValue Set AD Object Results: Total Attempts: $($AllResults.Count); Successes: $SuccessesCount; Failures: $FailuresCount."
                WriteLog -Message "Set-ImmutableIDAttributeValue Operations Completed."
            }
        }
    }
#end function Set-AttributeValue
