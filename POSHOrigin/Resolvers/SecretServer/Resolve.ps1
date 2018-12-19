[cmdletbinding()]
param(
    [parameter(Mandatory)]
    [psobject]$Options = $null
)

begin {
    Write-Debug -Message $msgs.rslv_pscredential_begin
}

process {

    $secretID = $options.secretID
    $password = ""
    $userName = ""
    $domainName = ""
    

	$ws = New-WebServiceProxy -uri $($options.serviceUri) -UseDefaultCredential
	$wsResult = $ws.GetSecret($secretID, $null, $null)

    foreach($item in $wsResult.Secret.Items)
    {
        if($item.IsPassword -eq $true)
        {
            $password = $item.Value
        }
        if($item.FieldName -eq "Username")
        {
            $userName = $item.Value
        }
        if($item.FieldName -eq "Domain")
        {
            $domainName = $item.Value
        }
    }

    if($null -ne $options.userName)
    {
        $userName = $options.userName
    }
    else 
    {
        if ($domainName -ne ""){
            $userName = "$domainName\$userName"
        }
    }

    $keySecure = $password | ConvertTo-SecureString -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList ($userName, $keySecure) 
    #Write-Verbose -Message ($msgs.rslv_pscredential_got_cred -f $options.userName)
    return $cred
}

end {
    Write-Debug -Message $msgs.rslv_pscredential_end
}