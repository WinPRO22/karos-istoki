Set-StrictMode -Version Latest

# AMo.exe 0x5F1AB2: subtract the rolling key, then add the decoded byte.
# Only the low byte of the initial argument 0x3042 affects the result.
function ConvertFrom-B1008Ten {
    param([Parameter(Mandatory)][byte[]]$Data)
    if ($Data.Length -eq 0 -or $Data.Length -gt 256) { throw 'Invalid TEN length.' }
    $key = 0x42
    $plain = [byte[]]::new($Data.Length)
    for ($i = 0; $i -lt $Data.Length; $i++) {
        $plain[$i] = ($Data[$i] - $key) -band 255
        $key = $Data[$i]
        if ($plain[$i] -ne 10 -and $plain[$i] -ne 13 -and
            ($plain[$i] -lt 32 -or $plain[$i] -gt 126)) {
            throw 'TEN endpoint contains non-ASCII or control bytes.'
        }
    }
    [Text.Encoding]::ASCII.GetString($plain)
}

function ConvertTo-B1008Ten {
    param([Parameter(Mandatory)][string]$Text)
    if ($Text.Length -eq 0 -or $Text.Length -gt 256) { throw 'Invalid TEN length.' }
    $key = 0x42
    $encoded = [byte[]]::new($Text.Length)
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $value = [int]$Text[$i]
        if ($value -ne 10 -and $value -ne 13 -and ($value -lt 32 -or $value -gt 126)) {
            throw 'TEN endpoint must be ASCII without embedded control bytes.'
        }
        $key = ($key + $value) -band 255
        $encoded[$i] = $key
    }
    return ,$encoded
}

function Get-B1008Endpoint {
    param([Parameter(Mandatory)][byte[]]$Data, [switch]$RequireLocal)
    $plain = ConvertFrom-B1008Ten $Data
    if ($plain -cnotmatch '\A([0-9]{1,3}(?:\.[0-9]{1,3}){3})\r\n([0-9]{1,5})(?:\r\n)?\z') {
        throw 'Expected two TEN lines: dotted IPv4 and decimal port.'
    }
    $address = $Matches[1]
    $port = [int]$Matches[2]
    foreach ($part in $address.Split('.')) {
        if ([int]$part -gt 255 -or ($part.Length -gt 1 -and $part[0] -eq '0')) {
            throw 'Non-canonical IPv4 address.'
        }
    }
    if ($port -lt 1 -or $port -gt 65535) { throw 'Invalid port.' }
    if ($RequireLocal -and ($address -cne '127.0.0.1' -or $port -ne 10001)) {
        throw 'Test client must target exactly 127.0.0.1:10001.'
    }
    [pscustomobject]@{ Address = $address; Port = $port }
}

function Test-B1008RuntimeLogPath {
    param([Parameter(Mandatory)][string]$RelativePath)
    return $RelativePath -match '\AWeber_log\\[0-9]{4}_[0-9]{2}_[0-9]{2}\.txt\z'
}

Export-ModuleMember -Function ConvertFrom-B1008Ten, ConvertTo-B1008Ten, Get-B1008Endpoint, Test-B1008RuntimeLogPath
