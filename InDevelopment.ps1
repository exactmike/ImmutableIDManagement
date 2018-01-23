function Set-TargetObjectFromSourceObjectCrossForest
    {
        [cmdletbinding(SupportsShouldProcess)]
        param
        (
            $SourceForestDrive #Source ADForest PSDriveName Without any path/punctuation
            ,
            $SourceObjectGUID
            ,
            $SourceImmutableIDAttribute = 'mS-DS-ConsistencyGUID'
            ,
            $TargetForestDrive #Target ADForest PSDriveName Without any path/punctuation
            ,
            $TargetObjectGUID
            ,
            $TargetImmutableIDAttribute = 'mS-DS-ConsistencyGUID'
        )
        Push-Location
        try
        {
            Set-Location $($SourceForestDrive + ':\') -ErrorAction Stop
            $SourceObjectFromGlobalCatalog = Get-AdObject -Identity $SourceObjectGUID -Property CanonicalName -ErrorAction Stop
            $SourceObjectDomain = Get-AdObjectDomain -adobject $SourceObjectFromGlobalCatalog -ErrorAction Stop
            $SourceObject = Get-AdObject -Identity $SourceObjectGUID -Server $SourceObjectDomain -Property CanonicalName,$SourceImmutableIDAttribute -ErrorAction Stop
            if ($null -eq $($SourceObject.$($SourceImmutableIDAttribute)))
            {
                Throw "Source Object $SourceObjectGUID's source Immutable ID attribute $SourceImmutableIDAttribute is NULL"
            }
        }
        catch
        {
            Pop-Location
            $_
            Throw "Source Object $sourceObjectGUID Failure for Source Forest PSDrive $sourceForestDrive"
        }
        try
        {
            Set-Location $($TargetForestDrive + ':\') -ErrorAction Stop
            $TargetObjectFromGlobalCatalog = Get-AdObject -Identity $TargetObjectGUID -Property CanonicalName -ErrorAction Stop
            $TargetObjectDomain = Get-AdObjectDomain -adobject $TargetObjectFromGlobalCatalog -ErrorAction Stop
            $TargetObject = Get-AdObject -Identity $TargetObjectGUID -Server $TargetObjectDomain -Property CanonicalName,$TargetImmutableIDAttribute -ErrorAction Stop
            if ($null -ne $($TargetObject.$($TargetImmutableIDAttribute)))
            {
                Throw "Target Object $TargetObjectGUID's target Immutable ID attribute $targetImmutableIDAttribute is NOT currently NULL"
            }
            if ($PSCmdlet.ShouldProcess($TargetObjectGUID,"Set-ADObject $TargetObjectGUID attribute $TargetImmutableIDAttribute with value $($SourceObject.$($SourceImmutableIDAttribute))"))
            {
                Set-ADObject -Identity $TargetObjectGUID -Add @{$TargetImmutableIDAttribute=$($SourceObject.$($SourceImmutableIDAttribute))} -Server $TargetObjectDomain -ErrorAction Stop -confirm:$false
            }
        }
        catch
        {
            Pop-Location
            $_
            Throw "Target Object $TargetObjectGUID Failure for Target Forest PSDrive $TargetForestDrive"
        }
        Pop-Location
    }
#end function Join-ADObjectByImmutableID