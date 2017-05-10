function Invoke-POSHOrigin {
    <#
        .SYNOPSIS
            Compiles and invokes a POSHOrigin configuration.
        .DESCRIPTION
            Compiles and invokes a POSHOrigin configuration. The custom object(s) passed into this function will be translated into DSC resource(s)
            and a DSC configuration will be compiled and executed.
        .PARAMETER InputObject
            One or more custom objects containing the required options for the DSC resource to be provisioned.
        .PARAMETER Path
            The path to a folder containing the POSHOrigin configuration file(s) to process or to a individual POSHOrigin file.
        .PARAMETER ProvisioningServer
            The name of the provisioning computer the DSC configuration will be applied to. Default value is retrieved from the provisioning_server
            parameter stored in $env:USERPROFILE.poshorigin\options.json. Normally this will be localhost unless manually changed.
        .PARAMETER PrettyPrint
            Parse the verbose output and display in an easier to ready format.
        .PARAMETER Confirm
            Prompts you for confirmation before running the cmdlet.
        .PARAMETER PassThru
            Return the result of the DSC run.
        .PARAMETER WhatIf
            Only execute the TEST functionality of DSC.

            NO RESOURCES WILL BE MODIFIED.
        .PARAMETER KeepMOF
            Switch to denote if the MOF file should NOT be deleted after DSC runs.
        .PARAMETER MakeItSo
            Injects a 'snoverism'
        .EXAMPLE
            Compiles and invokes a POSHOrigin configuration. Infrastructure resources defined in $myConfig will be tested for compliance and as
            necessary created, deleted, or modified.

            Invoke-POSHOrigin -InputObject $myConfig -Verbose
        .EXAMPLE
            Compiles and tests a POSHOrigin configuration. This will only test the DSC resources for compliance.
            NO RESOURCES WILL BE CREATED, DELETED, OR MODIFIED

            Invoke-POSHOrigin -InputObject $myConfig -Verbose -WhatIf
        .EXAMPLE
            Load in a POSHOrigin configuration and then execute it with pretty-printed output.

            $myConfig = Get-POSHOriginConfig -Path '.\config.ps1'
            $myConfig | Invoke-POSHOrigin -Verbose -PrettyPrint
        .EXAMPLE
            Make it so Number One.

            Invoke-POSHOrigin -InputObject $myConfig -Verbose -MakeItSo
    #>
    [cmdletbinding(
        SupportsShouldProcess,
        DefaultParameterSetName='Path',
        HelpUri='https://github.com/devblackops/POSHOrigin/wiki/Invoke-POSHOrigin')]
    param(
        [string]$ProvisioningServer = (_GetOption -Option 'provisioning_server'),

        [parameter(mandatory, position=0, ValueFromPipeline, ParameterSetName='Path')]
        [string]$Path,

        [Parameter(mandatory, position=0, ValueFromPipeline, ParameterSetName='InputObject')]
        [ValidateScript({ $_.PSObject.TypeNames[0] -eq 'POSHOrigin.Resource' })]
        [psobject[]]$InputObject,

        [switch]$PassThru,

        [switch]$MakeItSo,

        [switch]$KeepMOF,

        [switch]$PrettyPrint
    )

    begin {
        Write-Debug -Message $msgs.ipo_begin
        $data = @()

        $PrettyPrint = $PSBoundParameters.ContainsKey('PrettyPrint')

        # Start stopwatch
        $sw = [diagnostics.stopwatch]::StartNew()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $data = Get-POSHOriginConfig -Path $Path
        } else {
            $InputObject | foreach-object {
             $data += $_
            }
        }
    }

    end {
        # Temporarilly disable the PowerShell progress bar
        $oldProgPref = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'

        $results = $null

        if ($PSBoundParameters.ContainsKey('MakeItSo')) {
            Write-Verbose -Message $msgs.ipo_makeitso
            $picard = Get-Content -Path "$moduleRoot\picard.txt" -Raw
            Write-Verbose -Message "`n$picard"
        }

        # Create MOF
        $mofPath = _CompileConfig -ConfigData $data -ProvisioningServer $ProvisioningServer -WhatIf:$false

        if (Test-Path -Path $mofPath) {
            Write-Verbose -Message ($msgs.ipo_mof_generated -f $mofPath.FullName)

            # Publish MOF to provisioning server if not local.
            # Otherwise, start DSC configuration locally

            try {
                $executeRemote = ($ProvisioningServer -ne 'localhost' -and $ProvisioningServer -ne '.' -and $ProvisioningServer -ne $env:COMPUTERNAME)
                if ($executeRemote) {
                    Publish-DscConfiguration -Path (Split-Path -Path $mofPath -Parent) -ComputerName $ProvisioningServer -Confirm:$false
                    if ($PSCmdlet.ShouldProcess($msgs.ipo_should_msg)) {
                        $results = _InvokeDscConfiguration -ComputerName $ProvisioningServer -PrettyPrint $PrettyPrint
                    } else {
                        $results = _InvokeDscConfiguration -ComputerName $ProvisioningServer -PrettyPrint $PrettyPrint -TestOnly $true
                    }
                } else {
                    if ($PSCmdlet.ShouldProcess($msgs.ipo_should_msg)) {
                        $results = _InvokeDscConfiguration -Path (Split-Path -Path $mofPath -Parent) -PrettyPrint $PrettyPrint
                    } else {
                        $results = _InvokeDscConfiguration -Path (Split-Path -Path $mofPath -Parent) -PrettyPrint $PrettyPrint -TestOnly $true
                    }
                }
            } catch {
                Write-Error $_
            } finally {
                # Cleanup
                if (-Not $PSBoundParameters.ContainsKey('KeepMOF')) {
                    Remove-Item -Path $mofPath -Force -Confirm:$false -WhatIf:$false
                }
                Remove-DscConfigurationDocument -Stage Current, Pending -Force -Confirm:$false
            }

            # Reset the progress bar preference
            $global:ProgressPreference = $oldProgPref

            # Remove any downloaded git-based modules
            _CleanupDownloadedModules.ps1

            Write-Debug -Message $msgs.ipo_end
        } else {
            Write-Error -Message $msgs.ipo_mof_failure
        }

        # Stop stopwatch
        Write-Verbose -Message "Command finished in $($sw.Elapsed.TotalSeconds) seconds"
        $sw.stop()

        if ($PSBoundParameters.ContainsKey('PassThru')) {
            return $results
        }
    }
}