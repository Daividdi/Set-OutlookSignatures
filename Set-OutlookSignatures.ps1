﻿<#
Downloads centrally stored signatures, replaces variables, optionally sets default signatures.

Signatures can be applicable to all users, specific groups or specific mail addresses.

The script deletes locally available signatures, if they are no longer available centrally.
    Signature created manually by the user are not deleted. The script marks each downloaded
    signature with a specific HTML tag, which enables this cleaning feature.

The Outlook signature path is retrieved from the users registry, so the script is language independent.

The script does not consider secondary mailboxes, only primary mailboxes (mailboxes added as additional accounts).
    This is the same way Outlook handles mailboxes from a signature perspective.

Requires Outlook and Word, at least version 2010.

Error handling is implemented rudimentarily.

Outlook and the script can run simultaneously. New and changed signatures are available instantly,
    but changed settings which signatures are to be used as default signature require an Outlook restart. 


HTML FILE FORMAT
Only HTML files with the extension .HTM are supported.
    The script does not support .MSG, .EML, .MHT, .MHTML or .HTML files.

The file must be UTF8 encoded, or at least only contain UTF8 compatible characters.

The file must be a single HTML file. Additional files are not supported.
Graphics must either be embedded via a pulic URL, or be part of the HTML code as base64 encoded string.
Possible approaches
    Design the mail body in a HTML editor and use links to images, which can be accessed from the internet
    - OR -
    Design the mail body in a HTML editor that is able to convert image links to inline Data URI Base64 strings
    - OR -
    Design the mail body in Outlook
    Copy the mail body, paste it into Word and save it as “Website, filtered” (this reduces lots of Office HTML overhead)
    This creates a .HTM file and a folder containing pictures (if there are any)
    Use ConvertTo-SingleFileHTML.ps1 (comes with this script) or tools such as https://github.com/zTrix/webpage2html/
        to convert image links to inline Data URI Base64 strings


IMPORTANT FILE NAMING INFORMATION
The script copies every signature file name as-is, with one exception: When tags are defined in the file name,
    these tags are removed.
Tags must beplaced before the file extension and be separated from the base filename with a period.
Examples:
    'ITSV extern.htm' -> 'ITSV extern.htm', no changes
    'ITSV extern.[defaultNew].htm' -> 'ITSV extern.htm', tag(s) is/are removed
    'ITSV extern [deutsch].htm' ' -> 'ITSV extern [deutsch].htm', tag(s) is/are not removed, because they are separated from base filename
    'ITSV extern [deutsch].[defaultNew] [ITSV-SVS Alle Mitarbeiter].htm' ' -> 'ITSV extern [deutsch].htm', tag(s) is/are removed, because they are separated from base filename

Allowed filename tags
    [defaultNew]
    Set signature as default signature for new messages
    
    [defaultReplyFwd]
    Set signature as default signature für reply for forwarded mails
    
    [<NETBIOS-Domain> <Group SamAccountName>]
    Make this signature specific to any member (direct or indirect) of this group
    
    [<SMTP address>]
    Make this signature specific for the assigned mail address (all SMTP addresses of a mailbox are considered, not only the primary one)

    Filename tags can be combined, so a signature may be assigned to several groups and several mail addresses at the samt time.


SIGNATURE APPLICATION ORDER
    Signatures are applied in a specific order: Common signatures first, group signatures second,
        mail address specific signatures last.
    Common signatures are signatures with either no tag or only [defaultNew] and/or [defaultReplyFwd].
    Within these groups, signatures are applied alphabetically ascending.
    Every centrally stored signature is applied only once, as there is only one signature path in Outlook,
        and subfolders are not allowed - so the file names have to be unique.
    The script always starts with the mailboxes in the default Outlook profile,
        preferrably with the current users personal mailbox.


VARIABLE REPLACEMENT
Variables are case sensitive. Variables are replaced everywhere in the .HTM file, including href-Links.

With this feature, you can not only show mail addresses and telephone numbers in the signature,
but show them as a link which upon being clicked on opens a new mail message ("mailto:")
or dials the number ("tel:") via a locally installed softphone.

Available variables
    # Currently logged on user
    $CURRENTUSERGIVENNAME$: Given name
    $CURRENTUSERSURNAME$: Surname
    $CURRENTUSERNAMEWITHTITLES$: SVSTitelVorne Given Name Surname, SVSTitelHinten (ohne überflüssige Satzzeichen bei fehlenden Einzelattributen)
    $CURRENTUSERDEPARTMENT$: Department
    $CURRENTUSERTITLE$: Title
    $CURRENTUSERSTREETADDRESS$: StreetM
    $CURRENTUSERPOSTALCODE$: Postal code
    $CURRENTUSERLOCATION$: Location
    $CURRENTUSERCOUNTRY$: Country
    $CURRENTUSERTELEPHONE$: Telephone number
    $CURRENTUSERFAX$: Facsimile number
    $CURRENTUSERMOBILE$: Mobile phone
    $CURRENTUSERMAIL$: Mail address

    # Manager of currently logged on user
    Same variables as logged on user, $CURRENTUSERMANAGER[...]$ instead of $CURRENTUSER[...]$

    # Current mailbox
    Same variables as logged on user, $CURRENTMAILBOX[...]$ instead of $CURRENTUSER[...]$

    # Manager of current mailbox
    Same variables as logged on user, $CURRENTMAILBOXMANAGER[...]$ instead of $CURRENTMAILBOX[...]$


OUTLOOK WEB
If the currently logged on user has configured his personal mailbox in Outlook,
    the default signature for new emails is configured in Outlook Web automatically.
If the default signature for new mails matches the one used for replies and forwarded mail,
    this is also set in Outlook.
If different signatures for new and reply/forward are set, only the new signature is copied to Outlook Web.
If only a default signature for replies and forwards is set, only this new signature is copied to Outlook Web.
If there is no default signature in Outlook, Outlook Web settings are not changed.

All this happens with the credentials of the currently logged on user, without any interaction neccessary.
#>


$SignatureTemplatePath = '.\source'


#
# Do not change anything from here on
#

Clear-Host

try {
    $COMOutlook = New-Object -ComObject outlook.application
} catch {
    Write-Host 'Outlook not installed or not working correctly. Exiting.'
    exit 1
}

$OutlookRegistryVersion = [System.Version]::Parse($COMOutlook.Version)

if ($OutlookRegistryVersion.major -gt 16) {
    Write-Host "Outlook version $OutlookRegistryVersion is newer than 16 and not yet known. Please inform your administrator. Exiting."
    exit 1
} elseif ($OutlookRegistryVersion.major -eq 16) {
    $OutlookRegistryVersion = '16.0'
} elseif ($OutlookRegistryVersion.major -eq 15) {
    $OutlookRegistryVersion = '15.0'
} elseif ($OutlookRegistryVersion.major -eq 14) {
    $OutlookRegistryVersion = '14.0'
} else {
    Write-Host "Outlook version $OutlookRegistryVersion is below minimum required version 15 (Outlook 2010). Exiting."
    exit 1
}

if ($null -eq $OutlookRegistryVersion) {
    Write-Host 'Outlook not installed or not working correctly. Exiting.'
    exit 1
}


$OutlookDefaultProfile = $COMOutlook.DefaultProfileName


function Main {
    Write-Host 'Get AD properties of currently logged on user and his manager.'
    try {
        $ADPropsCurrentUser = ([adsisearcher]"(samaccountname=$env:username)").FindOne().Properties
    } catch {
        Write-Host '  Problem connecting to Active Directory. Exiting.'
        exit 1
    }
    try {
        $ADPropsCurrentUserManager = ([adsisearcher]('(distinguishedname=' + $ADPropsCurrentUser.manager + ')')).FindOne().Properties
    } catch {
        $ADPropsCurrentUserManager = $null
    }
    Write-Host 'Get Outlook signature file path(s).'
    $SignaturePaths = @()
    Get-ItemProperty 'hkcu:\software\microsoft\office\*\common\general' | Where-Object { $_.'Signatures' -ne '' } | ForEach-Object {
        Push-Location (Join-Path -Path $env:AppData -ChildPath 'Microsoft')
        $x = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($_.Signatures)
        if (Test-Path $x -IsValid) {
            if (-not (Test-Path $x -type container)) {
                New-Item -Path $x -ItemType directory -Force
            }
            $SignaturePaths += $x
            Write-Host "  $x"
        }
        Pop-Location
    }

    Write-Host 'Get mail addresses from Outlook profiles and corresponding registry paths.'
    $MailAddresses = @()
    $RegistryPaths = @()
    if ($OutlookDefaultProfile.length -eq '') {
        Get-ItemProperty "hkcu:\Software\Microsoft\Office\$OutlookRegistryVersion\Outlook\Profiles\*\9375CFF0413111d3B88A00104B2A6676\*" | Where-Object { $_.'Account Name' -like '*@*.*' } | ForEach-Object {
            $MailAddresses += $_.'Account Name'
            $RegistryPaths += $_.PSPath
            Write-Host "  $($_.PSPath -ireplace [regex]::escape('Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER'), $_.PSDrive)"
            Write-Host "    $($_.'Account Name')"
        }
    } else {
        # current users mailbox in default profile
        Get-ItemProperty "hkcu:\Software\Microsoft\Office\$OutlookRegistryVersion\Outlook\Profiles\$OutlookDefaultProfile\9375CFF0413111d3B88A00104B2A6676\*" | Where-Object { $_.'Account Name' -ieq $ADPropsCurrentUser.mail } | ForEach-Object {
            $MailAddresses += $_.'Account Name'
            $RegistryPaths += $_.PSPath
            Write-Host "  $($_.PSPath -ireplace [regex]::escape('Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER'), $_.PSDrive)"
            Write-Host "    $($_.'Account Name')"
        }
        # other mailboxes in default profile
        Get-ItemProperty "hkcu:\Software\Microsoft\Office\$OutlookRegistryVersion\Outlook\Profiles\$OutlookDefaultProfile\9375CFF0413111d3B88A00104B2A6676\*" | Where-Object { ($_.'Account Name' -like '*@*.*') -and ($_.'Account Name' -ine $ADPropsCurrentUser.mail) } | ForEach-Object {
            $MailAddresses += $_.'Account Name'
            $RegistryPaths += $_.PSPath
            Write-Host "  $($_.PSPath -ireplace [regex]::escape('Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER'), $_.PSDrive)"
            Write-Host "    $($_.'Account Name')"
        }
        # all other mailboxes in all other profiles
        Get-ItemProperty "hkcu:\Software\Microsoft\Office\$OutlookRegistryVersion\Outlook\Profiles\*\9375CFF0413111d3B88A00104B2A6676\*" | Where-Object { $_.'Account Name' -like '*@*.*' } | ForEach-Object {
            if ($RegistryPaths -notcontains $_.PSPath) { 
                $MailAddresses += $_.'Account Name'
                $RegistryPaths += $_.PSPath
                Write-Host "  $($_.PSPath -ireplace [regex]::escape('Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER'), $_.PSDrive)"
                Write-Host "    $($_.'Account Name')"
            }
        }
    }

    Write-Host 'Get all signature files and categorize them.'
    if ((Test-Path $SignatureTemplatePath -PathType Container) -eq $false) {
        Write-Host "  Problem connecting to or reading from folder '$SignatureTemplatePath'. Exiting."
        exit 1
    }

    $SignatureFilesCommon = @{}
    $SignatureFilesGroup = @{}
    $SignatureFilesGroupFilePart = @{}
    $SignatureFilesMailbox = @{}
    $SignatureFilesMailboxFilePart = @{}
    $SignatureFilesDefaultNew = @{}
    $SignatureFilesDefaultReplyFwd = @{}
    $global:SignatureFilesDone = @()

    foreach ($SignatureFile in (Get-ChildItem -Path $SignatureTemplatePath -File)) {
        Write-Host ("  '$($SignatureFile.Name)'")
        $x = $SignatureFile.name -split '\.(?![\w\s\d]*\[*(\]|@))'
        if ($x.count -ge 3) {
            $SignatureFilePart = $x[-2]
            $SignatureFileTargetName = ($x[($x.count * -1)..-3] -join '.') + '.' + $x[-1]
        } else {
            $SignatureFilePart = ''
            $SignatureFileTargetName = $SignatureFile.Name
        }

        [regex]::Matches((($SignatureFilePart -replace '(?i)\[DefaultNew\]', '') -replace '(?i)\[DefaultReplyFwd\]', ''), '\[(.*?)\]').captures.value | ForEach-Object {
            if ($_ -eq $null) {
                Write-Host '    Common signature.'
                $SignatureFilesCommon.add($SignatureFile.FullName, $SignatureFileTargetName)
            } elseif ($_ -match '(.*?)@(.*?)\.(.*?)') {
                Write-Host '    Mailbox specific signature.'
                $SignatureFilesMailbox.add($SignatureFile.FullName, $SignatureFileTargetName)
                $SignatureFilesMailboxFilePart.add($SignatureFile.FullName, $SignatureFilePart)
            } else {
                Write-Host '    Group specific signature.'
                $SignatureFilesGroup.add($SignatureFile.FullName, $SignatureFileTargetName)
                $SignatureFilesGroupFilePart.add($SignatureFile.FullName, $SignatureFilePart)
            } 
        }

        if ($SignatureFilePart -match '(?i)\[DefaultNew\]') {
            $SignatureFilesDefaultNew.add($SignatureFile.FullName, $SignatureFileTargetName)
            Write-Host '    Default signature for new mails.'
        }

        if ($SignatureFilePart -match '(?i)\[DefaultReplyFwd\]') {
            $SignatureFilesDefaultReplyFwd.add($SignatureFile.FullName, $SignatureFileTargetName)
            Write-Host '    Default signature for replies and forwards.'
        }
    }


    # Start Word, as we need it to edit signatures
    try {
        $MSWord = New-Object -ComObject word.application
    } catch {
        Write-Host 'Outlook not installed or not working correctly. Exiting.'
        exit 1
    }

    # Process each mail address only once, but each corresponding registry path
    for ($i = 0; $i -lt $MailAddresses.count; $i++) {
        if ($i -le $MailAddresses.IndexOf($MailAddresses[$i])) {
            Write-Host "Mailbox $($MailAddresses[$i])."

            Write-Host '  Get AD properties of mailbox.'
            $ADPropsCurrentMailbox = ([adsisearcher]('(mail=' + $MailAddresses[$i] + ')')).FindOne().Properties
            try {
                $ADPropsCurrentMailboxManager = ([adsisearcher]('(distinguishedname=' + $ADPropsCurrentMailbox.manager + ')')).FindOne().Properties
            } catch {
                $ADPropsCurrentMailboxManager = $null
            }

            Write-Host '  Get group membership.'
            $Groups = @()
            $strFilter = ('(member:1.2.840.113556.1.4.1941:=' + $ADPropsCurrentMailbox.distinguishedname + ')')
            $objSearcher = New-Object System.DirectoryServices.DirectorySearcher
            # The script assumes, that SV_mail customer with an own Active Directory forest will have their signature groups somewhere in sv-services.at,
            # as there are the mailboxes, distribution lists etc.
            # If these groups are held in customer's own AD, change SearchRoot to the correct domain name or uncomment the line discovering the root domain of the logged on user
            # The script does currently not work across Active Directory forests connect with trusts
            #$objSearcher.SearchRoot = "GC://$((New-Object System.DirectoryServices.DirectoryEntry("LDAP://rootDSE")).rootDomainNamingContext)"
            $objSearcher.SearchRoot = 'GC://DC=sv-services,DC=at'
            $objSearcher.PageSize = 1000
            $objSearcher.Filter = $strFilter
            $objSearcher.SearchScope = 'Subtree'
            $objSearcher.PropertiesToLoad.Add('name') | Out-Null
            $objSearcher.PropertiesToLoad.Add('msds-principalname') | Out-Null
            $colResults = $objSearcher.FindAll()
            foreach ($objResult in $colResults) {
                # msds-principalname contains the domain, but the group name may not reflect the display name
                $Groups += (($objResult.Properties.'msds-principalname' -split '\\')[0] + ' ' + $objResult.Properties.'name')
                Write-Host "    $($Groups[-1])"
            }

            Write-Host '  Get SMTP addresses.'
            $CurrentMailboxSMTPAddresses = @()
            $ADPropsCurrentMailbox.proxyaddresses | ForEach-Object {
                if ([string]$_ -ilike 'smtp:*') {
                    $CurrentMailboxSMTPAddresses += [string]$_ -ireplace 'smtp:', ''
                    Write-Host ('    ' + ([string]$_ -ireplace 'smtp:', ''))
                }
            }

            Write-Host '  Process common signatures.'
            foreach ($h in $SignatureFilesCommon.GetEnumerator()) {
                Set-Signatures
            }

            Write-Host '  Process group signatures.'
            $TempHash = @{}
            foreach ($x in $SignatureFilesGroupFilePart.GetEnumerator()) {
                $Groups | ForEach-Object {
                    if ($x.Value.tolower().Contains('[' + $_.tolower() + ']')) {
                        $TempHash.add($x.Name, $SignatureFilesGroup[$x.Name])    
                    }
                }
            }
            foreach ($h in $TempHash.GetEnumerator()) {
                Set-Signatures
            }

            Write-Host '  Process mail address specific signatures.'
            $TempHash = @{}
            foreach ($x in $SignatureFilesMailboxFilePart.GetEnumerator()) {
                foreach ($y in $CurrentMailboxSMTPAddresses) {
                    if ($x.Value.tolower().contains('[' + $y.tolower() + ']')) {
                        $TempHash.add($x.Name, $SignatureFilesMailbox[$x.Name])    
                    }
                }
            }
            foreach ($h in $TempHash.GetEnumerator()) {
                Set-Signatures
            }
        }

        # Outlook Web Access
        if ($ADPropsCurrentMailbox.mail -ieq $ADPropsCurrentUser.mail) {
            Write-Host '  Setting Outlook Web signature.'
            # if the mailbox of the currenlty logged on user is part of his default Outlook Profile, copy the signature to OWA
            for ($j = 0; $j -lt $MailAddresses.count; $j++) {
                if ($MailAddresses[$j] -ieq [string]$ADPropsCurrentUser.mail) {
                    if ($RegistryPaths[$j] -like ('*\Outlook\Profiles\' + $OutlookDefaultProfile + '\9375CFF0413111d3B88A00104B2A6676\*')) {
                        $TempNewSig = Get-ItemPropertyValue -LiteralPath $RegistryPaths[$j] -Name 'New Signature'
                        $TempReplySig = Get-ItemPropertyValue -LiteralPath $RegistryPaths[$j] -Name 'Reply-Forward Signature'

                        if (($TempNewSig -eq '') -and ($TempReplySig -eq '')) {
                            Write-Host '    No default signatures defined, nothing to do.'        
                            $TempOWASigFile = $null
                            $TempOWASigSetNew = $null
                            $TempOWASigSetReply = $null
                        }
                        
                        if (($TempNewSig -ne '') -and ($TempReplySig -eq '')) {
                            Write-Host '    Signature for new mails found.'
                            $TempOWASigFile = $TempNewSig
                            $TempOWASigSetNew = 'True'
                            $TempOWASigSetReply = 'False'
                        }

                        if (($TempNewSig -eq '') -and ($TempReplySig -ne '')) {
                            Write-Host '    Default signature for reply/forward found.'
                            $TempOWASigFile = $TempReplySig
                            $TempOWASigSetNew = 'False'
                            $TempOWASigSetReply = 'True'
                        }


                        if ((($TempNewSig -ne '') -and ($TempReplySig -ne '')) -and ($TempNewSig -ine $TempReplySig)) {
                            Write-Host '    Different default signatures for new and reply/forward found. Using new signature.'
                            $TempOWASigFile = $TempNewSig
                            $TempOWASigSetNew = 'True'
                            $TempOWASigSetReply = 'False'
                        }

                        if ((($TempNewSig -ne '') -and ($TempReplySig -ne '')) -and ($TempNewSig -ieq $TempReplySig)) {
                            Write-Host '    Same default signature for new and reply/forward.'
                            $TempOWASigFile = $TempNewSig
                            $TempOWASigSetNew = 'True'
                            $TempOWASigSetReply = 'True'
                        }

                        if ($null -ne $TempOWASigFile) {
                            Import-Module -Name '.\Microsoft.Exchange.WebServices.dll'
                            $exchService = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService
                            $exchService.UseDefaultCredentials = $true
                            $exchService.AutodiscoverUrl($ADPropsCurrentUser.mail)
                            $folderid = New-Object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Root, $MailboxName)     
                            #Specify the Root folder where the FAI Item is  
                            $UsrConfig = [Microsoft.Exchange.WebServices.Data.UserConfiguration]::Bind($exchService, 'OWA.UserOptions', $folderid, [Microsoft.Exchange.WebServices.Data.UserConfigurationProperties]::All)  
                            $hsHtmlSignature = (Get-Content -LiteralPath (Join-Path -Path $SignaturePaths[0] -ChildPath ($TempOWASigFile + '.htm')) -Raw).ToString()
                            $stTextSig = (Get-Content -LiteralPath (Join-Path -Path $SignaturePaths[0] -ChildPath ($TempOWASigFile + '.txt')) -Raw).ToString()  

                            if ($UsrConfig.Dictionary.ContainsKey('signaturehtml')) {
                                $UsrConfig.Dictionary['signaturehtml'] = $hsHtmlSignature  
                            } else {  
                                $UsrConfig.Dictionary.Add('signaturehtml', $hsHtmlSignature)  
                            }  

                            if ($UsrConfig.Dictionary.ContainsKey('signaturetext')) {
                                $UsrConfig.Dictionary['signaturetext'] = $stTextSig  
                            } else {  
                                $UsrConfig.Dictionary.Add('signaturetext', $stTextSig)  
                            }

                            if ($UsrConfig.Dictionary.ContainsKey('autoaddsignature')) {
                                $UsrConfig.Dictionary['autoaddsignature'] = $TempOWASigSetNew  
                            } else {  
                                $UsrConfig.Dictionary.Add('autoaddsignature', $TempOWASigSetNew)
                            }

                            if ($UsrConfig.Dictionary.ContainsKey('autoaddsignatureonreply')) {
                                $UsrConfig.Dictionary['autoaddsignatureonreply'] = $TempOWASigSetReply
                            } else {  
                                $UsrConfig.Dictionary.Add('autoaddsignatureonreply', $TempOWASigSetReply)
                            }

                            $UsrConfig.Update()
                        }
                    }
                }
            }
        }
    }

    # Quit word, as all signatures have been edited
    $MSWord.Quit()

    # Delete old signatures created by this script, which are no long available ni $source
    # We check all local signature for a specific marker in HTML code, so we don't touch user created signatures
    Write-Host 'Removing old signatures created by this script, which are no longer centrally available.'
    $SignaturePaths | ForEach-Object {
        Get-ChildItem $_ -Filter '*.htm' -File | ForEach-Object {
            if ((Get-Content -LiteralPath $_.fullname -Raw) -like ('*' + $MarkerTag + '*')) {
                if (($_.name -notin $SignatureFilesCommon.values) -and ($_.name -notin $SignatureFilesMailbox.Values) -and ($_.name -notin $SignatureFilesGroup.Values)) {
                    Write-Host ("  '" + $([System.IO.Path]::ChangeExtension($_.fullname, '')) + "*'")
                    Remove-Item -LiteralPath $_.fullname -Force -ErrorAction silentlycontinue
                    Remove-Item -LiteralPath ($([System.IO.Path]::ChangeExtension($_.fullname, '.rtf'))) -Force -ErrorAction silentlycontinue
                    Remove-Item -LiteralPath ($([System.IO.Path]::ChangeExtension($_.fullname, '.txt'))) -Force -ErrorAction silentlycontinue
                }
            }
        }
    }
}

function Set-Signatures {
    $MarkerTag = '<meta name=data-SignatureFileInfo content="Set-OutlookSignaturesSV_mail.ps1">'
    
    Write-Host "    '$($h.Name)'"

    $SignatureFileAlreadyDone = ($global:SignatureFilesDone -contains $($h.Name))
    if ($SignatureFileAlreadyDone) {
        Write-Host '      File already processed before.'
    } else {
        $global:SignatureFilesDone += $($h.Name)
    }

    if ($SignatureFileAlreadyDone -eq $false) {
        $tempFileContent = Get-Content -LiteralPath $h.Name -Raw -Encoding UTF8
        if ($tempFileContent.Contains([char]0xfffd)) {
            Write-Host '      File is not UTF-8 encoded or contains byte sequences not valid in UTF-8, ignoring file.'
            return
        }

        Write-Host '      Replace variables.'
        $ReplaceHash = @{}

        # Currently logged on user
        $replaceHash.Add('$CURRENTUSERGIVENNAME$', [string]$ADPropsCurrentUser.givenname)
        $replaceHash.Add('$CURRENTUSERSURNAME$', [string]$ADPropsCurrentUser.sn)
        $replaceHash.Add('$CURRENTUSERNAMEWITHTITLES$', ((((([string]$ADPropsCurrentUser.svstitelvorne, [string]$ADPropsCurrentUser.givenname, [string]$ADPropsCurrentUser.sn) | Where-Object { $_ -ne '' }) -join ' '), [string]$ADPropsCurrentUser.svstitelhinten) | Where-Object { $_ -ne '' }) -join ', ')        
        $replaceHash.Add('$CURRENTUSERDEPARTMENT$', [string]$ADPropsCurrentUser.department)
        $replaceHash.Add('$CURRENTUSERTITLE$', [string]$ADPropsCurrentUser.title)
        $replaceHash.Add('$CURRENTUSERSTREETADDRESS$', [string]$ADPropsCurrentUser.streetaddress)
        $replaceHash.Add('$CURRENTUSERPOSTALCODE$', [string]$ADPropsCurrentUser.postalcode)
        $replaceHash.Add('$CURRENTUSERLOCATION$', [string]$ADPropsCurrentUser.l)
        $replaceHash.Add('$CURRENTUSERCOUNTRY$', [string]$ADPropsCurrentUser.co)
        $replaceHash.Add('$CURRENTUSERTELEPHONE$', [string]$ADPropsCurrentUser.telephonenumber)
        $replaceHash.Add('$CURRENTUSERFAX$', [string]$ADPropsCurrentUser.facsimiletelephonenumber)
        $replaceHash.Add('$CURRENTUSERMOBILE$', [string]$ADPropsCurrentUser.mobile)
        $replaceHash.Add('$CURRENTUSERMAIL$', [string]$ADPropsCurrentUser.mail)

        # Manager of currently logged on user
        $replaceHash.Add('$CURRENTUSERMANAGERGIVENNAME$', [string]$ADPropsCurrentUserManager.givenname)
        $replaceHash.Add('$CURRENTUSERMANAGERSURNAME$', [string]$ADPropsCurrentUserManager.sn)
        $replaceHash.Add('$CURRENTUSERMANAGERNAMEWITHTITLES$', ((((([string]$ADPropsCurrentUserManager.svstitelvorne, [string]$ADPropsCurrentUserManager.givenname, [string]$ADPropsCurrentUserManager.sn) | Where-Object { $_ -ne '' }) -join ' '), [string]$ADPropsCurrentUserManager.svstitelhinten) | Where-Object { $_ -ne '' }) -join ', ')        
        $replaceHash.Add('$CURRENTUSERMANAGERDEPARTMENT$', [string]$ADPropsCurrentUserManager.department)
        $replaceHash.Add('$CURRENTUSERMANAGERTITLE$', [string]$ADPropsCurrentUserManager.title)
        $replaceHash.Add('$CURRENTUSERMANAGERSTREETADDRESS$', [string]$ADPropsCurrentUserManager.streetaddress)
        $replaceHash.Add('$CURRENTUSERMANAGERPOSTALCODE$', [string]$ADPropsCurrentUserManager.postalcode)
        $replaceHash.Add('$CURRENTUSERMANAGERLOCATION$', [string]$ADPropsCurrentUserManager.l)
        $replaceHash.Add('$CURRENTUSERMANAGERCOUNTRY$', [string]$ADPropsCurrentUserManager.co)
        $replaceHash.Add('$CURRENTUSERMANAGERTELEPHONE$', [string]$ADPropsCurrentUserManager.telephonenumber)
        $replaceHash.Add('$CURRENTUSERMANAGERFAX$', [string]$ADPropsCurrentUserManager.facsimiletelephonenumber)
        $replaceHash.Add('$CURRENTUSERMANAGERMOBILE$', [string]$ADPropsCurrentUserManager.mobile)
        $replaceHash.Add('$CURRENTUSERMANAGERMAIL$', [string]$ADPropsCurrentUserManager.mail)

        # Current mailbox
        $replaceHash.Add('$CURRENTMAILBOXGIVENNAME$', [string]$ADPropsCurrentMailbox.givenname)
        $replaceHash.Add('$CURRENTMAILBOXSURNAME$', [string]$ADPropsCurrentMailbox.sn)
        $replaceHash.Add('$CURRENTMAILBOXNAMEWITHTITLES$', ((((([string]$ADPropsCurrentMailbox.svstitelvorne, [string]$ADPropsCurrentMailbox.givenname, [string]$ADPropsCurrentMailbox.sn) | Where-Object { $_ -ne '' }) -join ' '), [string]$ADPropsCurrentMailbox.svstitelhinten) | Where-Object { $_ -ne '' }) -join ', ')        
        $replaceHash.Add('$CURRENTMAILBOXDEPARTMENT$', [string]$ADPropsCurrentMailbox.department)
        $replaceHash.Add('$CURRENTMAILBOXTITLE$', [string]$ADPropsCurrentMailbox.title)
        $replaceHash.Add('$CURRENTMAILBOXSTREETADDRESS$', [string]$ADPropsCurrentMailbox.streetaddress)
        $replaceHash.Add('$CURRENTMAILBOXPOSTALCODE$', [string]$ADPropsCurrentMailbox.postalcode)
        $replaceHash.Add('$CURRENTMAILBOXLOCATION$', [string]$ADPropsCurrentMailbox.l)
        $replaceHash.Add('$CURRENTMAILBOXCOUNTRY$', [string]$ADPropsCurrentMailbox.co)
        $replaceHash.Add('$CURRENTMAILBOXTELEPHONE$', [string]$ADPropsCurrentMailbox.telephonenumber)
        $replaceHash.Add('$CURRENTMAILBOXFAX$', [string]$ADPropsCurrentMailbox.facsimiletelephonenumber)
        $replaceHash.Add('$CURRENTMAILBOXMOBILE$', [string]$ADPropsCurrentMailbox.mobile)
        $replaceHash.Add('$CURRENTMAILBOXMAIL$', [string]$ADPropsCurrentMailbox.mail)

        # Manager of current mailbox
        $replaceHash.Add('$CURRENTMAILBOXMANAGERGIVENNAME$', [string]$ADPropsCurrentMailbox.givenname)
        $replaceHash.Add('$CURRENTMAILBOXMANAGERSURNAME$', [string]$ADPropsCurrentMailbox.sn)
        $replaceHash.Add('$CURRENTMAILBOXMANAGERNAMEWITHTITLES$', ((((([string]$ADPropsCurrentMailbox.svstitelvorne, [string]$ADPropsCurrentMailbox.givenname, [string]$ADPropsCurrentMailbox.sn) | Where-Object { $_ -ne '' }) -join ' '), [string]$ADPropsCurrentMailbox.svstitelhinten) | Where-Object { $_ -ne '' }) -join ', ')        
        $replaceHash.Add('$CURRENTMAILBOXMANAGERDEPARTMENT$', [string]$ADPropsCurrentMailbox.department)
        $replaceHash.Add('$CURRENTMAILBOXMANAGERTITLE$', [string]$ADPropsCurrentMailbox.title)
        $replaceHash.Add('$CURRENTMAILBOXMANAGERSTREETADDRESS$', [string]$ADPropsCurrentMailbox.streetaddress)
        $replaceHash.Add('$CURRENTMAILBOXMANAGERPOSTALCODE$', [string]$ADPropsCurrentMailbox.postalcode)
        $replaceHash.Add('$CURRENTMAILBOXMANAGERLOCATION$', [string]$ADPropsCurrentMailbox.l)
        $replaceHash.Add('$CURRENTMAILBOXMANAGERCOUNTRY$', [string]$ADPropsCurrentMailbox.co)
        $replaceHash.Add('$CURRENTMAILBOXMANAGERTELEPHONE$', [string]$ADPropsCurrentMailbox.telephonenumber)
        $replaceHash.Add('$CURRENTMAILBOXMANAGERFAX$', [string]$ADPropsCurrentMailbox.facsimiletelephonenumber)
        $replaceHash.Add('$CURRENTMAILBOXMANAGERMOBILE$', [string]$ADPropsCurrentMailbox.mobile)
        $replaceHash.Add('$CURRENTMAILBOXMANAGERMAIL$', [string]$ADPropsCurrentMailbox.mail)


        foreach ($replaceKey in $replaceHash.Keys) {
            $tempFileContent = $tempFileContent.replace($replaceKey, $replaceHash.$replaceKey)
        }

        
        Write-Host '      Add marker to HTML.'
        if ($tempFileContent -notlike "*$MarkerTag*") {
            if ($tempFileContent -like '*<head>*') {
                $tempFileContent = $tempFileContent -ireplace ('<HEAD>', ('<head>' + $MarkerTag))
            } else {
                $tempFileContent = $tempFileContent -ireplace ('<HTML>', ('<HTML><head>' + $MarkerTag + '</head>'))
            }
        }


        $SignaturePaths | ForEach-Object {
            Write-Host "      -> '$(Join-Path -Path $_ -ChildPath $h.value)'"
            $tempFileContent | Out-File -LiteralPath (Join-Path -Path $_ -ChildPath $h.value) -Encoding UTF8 -Force

            Write-Host '        Open signature file in Word.'
            $saveFormat = [Enum]::Parse([Microsoft.Office.Interop.Word.WdOpenFormat], 'wdOpenFormatWebPages')
            $path = $(Join-Path -Path $_ -ChildPath $h.value).tostring()
            $MSWord.Documents.Open([ref]$path, $false) | Out-Null
 
            Write-Host '        Convert to RTF.'
            # Convert to RTF
            $saveFormat = [Enum]::Parse([Microsoft.Office.Interop.Word.WdSaveFormat], 'wdFormatRTF')
            $path = $([System.IO.Path]::ChangeExtension((Join-Path -Path $_ -ChildPath $h.value), '.rtf'))
            $MSWord.ActiveDocument.SaveAs([ref]$path, [ref]$saveFormat)

            Write-Host '        Convert to TXT.'
            $saveFormat = [Enum]::Parse([Microsoft.Office.Interop.Word.WdSaveFormat], 'wdFormatText')
            $path = $([System.IO.Path]::ChangeExtension((Join-Path -Path $_ -ChildPath $h.value), '.txt'))
            $MSWord.ActiveDocument.SaveAs([ref]$path, [ref]$saveFormat)

            Write-Host '        Close File.'
            $MSWord.ActiveDocument.Close($false)
        }
    }

    # Set default signature for new mails
    if ($SignatureFilesDefaultNew.contains($h.name)) {
        for ($j = 0; $j -lt $MailAddresses.count; $j++) {
            if ($MailAddresses[$j] -eq $MailAddresses[$i]) {
                Write-Host '      Set signature as default for new messages.'
                Set-ItemProperty -Path $RegistryPaths[$j] -Name 'New Signature' -Type String -Value (($h.value -split '\.' | Select-Object -SkipLast 1) -join '.') -Force
            }
        }
    }

    # Set default signature for replies and forwarded mails
    if ($SignatureFilesDefaultReplyFwd.contains($h.name)) {
        for ($j = 0; $j -lt $MailAddresses.count; $j++) {
            if ($MailAddresses[$j] -eq $MailAddresses[$i]) {
                Write-Host '      Set signature as default for reply/forward messages.'
                Set-ItemProperty -Path $RegistryPaths[$j] -Name 'Reply-Forward Signature' -Type String -Value (($h.value -split '\.' | Select-Object -SkipLast 1) -join '.') -Force
            }
        }
    }
}


Main