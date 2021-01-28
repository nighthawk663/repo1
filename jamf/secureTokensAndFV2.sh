#!/bin/bash
# This script was originally intended to be used with JAMF Self Service. It will enable SecureToken for the currently logged in user account
# and either add it to the list of to FileVault enabled users or enable FileVault using a Personal Recovery Key.
# Modified by Len to run as a check-in triggered policy

# Your policy must include script parameters for a SecureToken enabled administrator username and password. For more information
# on using script parameters, please see https://www.jamf.com/jamf-nation/articles/146/script-parameters.

# Script by Len, 2019/04/09. Composed largely by blending two scripts together.
# The first provided during our jumpstart from Jamf
# The second from this blog (a Jamf employee) https://travellingtechguy.eu/script-secure-tokens-mojave/
# The direct-link to the git code for the second is https://raw.githubusercontent.com/TravellingTechGuy/manageSecureTokens/master/manageSecureTokens.sh
# And then adding a bunch of logging and fighting with AppleScript.
# 2020/10/20: Adding re-check function at start because somehow the extension attribute is slipping in Jamf causing this to re-run unnecessarily

adminUser="$4"
adminPassword="$5"
userName2="$6"
tempLog="/tmp/fv2Fix.log"

## Double-check that we actually need this run
# Secure Token check
if [[ $("/usr/sbin/sysadminctl" -secureTokenStatus "$adminUser" 2>&1) =~ "ENABLED" ]]; then
    adminToken=true
else
    adminToken=false
fi
# FileVault Check
if fdesetup status | grep -q "FileVault is On" && fdesetup list | grep -q "$adminUser"; then
    fdeToken=true
else
    fdeToken=false
fi
# If both are okay, exit gracefully.
if $adminToken && $fdeToken; then
    echo "Secure Tokens and 2FA already set up"
    exit 0
fi

# Brand Icons
devotedLogo="/Library/User Pictures/devoted-logomark.tiff"
selfServiceBrandIcon="/Users/$3/Library/Application Support/com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png"
jamfBrandIcon="/Library/Application Support/JAMF/Jamf.app/Contents/Resources/AppIcon.icns"
fileVaultIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FileVaultIcon.icns"

echo "Determining branding icon to use..." | tee -a $tempLog
if [[ -f $devotedLogo ]]; then
  brandIcon=$devotedLogo
elif [[ -f $selfServiceBrandIcon ]]; then
  brandIcon=$selfServiceBrandIcon
elif [[ -f $jamfBrandIcon ]]; then
  brandIcon=$jamfBrandIcon
else
brandIcon=$fileVaultIcon
fi

echo "Brand Icon: ${brandIcon}" | tee -a $tempLog

# Get the current logged in user
currentUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
echo "Current user: ${currentUser}" | tee -a $tempLog

# Check if our admin has a Secure Token
echo "Determining if admin has a secure token" | tee -a $tempLog
if [[ $("/usr/sbin/sysadminctl" -secureTokenStatus "$adminUser" 2>&1) =~ "ENABLED" ]]; then
	adminToken="true"
else
	adminToken="false"
fi
echo "Admin Token: $adminToken" | tee -a $tempLog

# Check if FileVault is Enabled
echo "Checking if FileVault is Enabled..." | tee -a $tempLog
if [[ $("/usr/bin/fdesetup" status 2>&1) == "FileVault is On." ]]; then
    fvStatus="true"

    fvAdminEnabled=$( fdesetup list | grep -c "$adminUser" )
    if [[ $fvAdminEnabled == 1 ]]; then
        fvAdminEnabled="true"
    else
        fvAdminEnabled="false"
    fi

    fvUserEnabled=$( fdesetup list | grep -c "$currentUser" )
    if [[ $fvUserEnabled == 1 ]]; then
        fvUserEnabled="true"
    else
        fvUserEnabled="false"
    fi
else
    fvStatus="false"
    fvUserEnabled="false"
    fvAdminEnabled="false"
fi
echo "FV Status: $fvStatus" | tee -a $tempLog

# Check Secure Tokens Status - Do we have any Token Holder?
echo "Checking Secure Token Status. Do we have any holders?" | tee -a $tempLog
if [[ $("/usr/sbin/diskutil" apfs listcryptousers / 2>&1) =~ "No cryptographic users" ]]; then
    tokenStatus="false"
else
    tokenStatus="true"	
fi
echo "Token Status $tokenStatus" | tee -a $tempLog

# Check if end user is admin
echo "Checking if End User is Admin" | tee -a $tempLog
if [[ $("/usr/sbin/dseditgroup" -o checkmember -m "$currentUser" admin / 2>&1) =~ "yes" ]]; then
    userType="Admin"
else
    userType="Not admin"
fi
echo "User type: $userType" | tee -a $tempLog

# Check Token status for end user
echo "Checking Token Status for End User" | tee -a $tempLog
if [[ $("/usr/sbin/sysadminctl" -secureTokenStatus "$currentUser" 2>&1) =~ "ENABLED" ]]; then
    userToken="true"
else
    userToken="false"
fi
echo "User Token: $userToken" | tee -a $tempLog


# If both end user and additional admin have a secure token
echo "Do both end user and management have secure tokens?" | tee -a $tempLog
if [[ $userToken = "true" && $adminToken = "true" ]]; then
    echo "Tokens are good!" | tee -a $tempLog
#    exit 0
fi


# Prompt for password
# Setting the loop counter and invalid password
i=1
passDSCLCheck=400
# If password is not valid, loop and ask again"
while [[ "$passDSCLCheck" != "0" ]]; do
    echo "Prompting ${currentUser} for password, Loop ${i}" | tee -a $tempLog
    userPass=$(sudo -u "${currentUser}" /usr/bin/osascript -e "
        on run
        Tell application \"System Events\" to display dialog \"Hello from Devoted IT!\" & return & \"Enter login password for '${currentUser}' to correct a FileVault issue\" & return & \"For more information, see\" & return & return & \"  http://office.devoted.com/mac-fv2  \" & return & \"(Google SSO login required)\" default answer \"\" with title \"Devoted FileVault Configuration\" with text buttons {\"Ok\"} default button 1 with icon POSIX file \"$brandIcon\" with hidden answer
        set userPass to text returned of the result
        return userPass
        end run"
    )
    
    passDSCLCheck=$(dscl /Local/Default authonly "$currentUser" "${userPass}"; echo $?)
    i=$(( i + 1 ))

    if [[ $i -ge 100 ]]; then
        echo "Looped for 100 times!!! ABORT!!" | tee -a $tempLog
        exit 1
    fi

done 

if [ "$passDSCLCheck" -eq 0 ]; then
    echo "Password OK for $currentUser" | tee -a $tempLog
fi

adminPassDSCLCheck=$(dscl /Local/Default authonly "$adminUser" "${adminPassword}"; echo $?)

if [[ $adminPassDSCLCheck == 0 ]]; then
    echo "Admin Password OK"
else
    echo "Admin Password failed!"
    exit 2
fi

### Actually get to work fixing this stuff

# If additional admin has a token but end user does not
if [[ $adminToken = "true" && $userToken = "false" ]]; then
    echo "Additional Admin has a token, but end user does not" | tee -a $tempLog
    sysadminctl -adminUser "$adminUser" -adminPassword "${adminPassword}" -secureTokenOn "$currentUser" -password "${userPass}"
    echo "Token granted to end user by $adminUser!" | tee -a $tempLog
    
    echo "List of cryptoUsers:" | tee -a $tempLog
    diskutil apfs listcryptousers / | tee -a $tempLog
fi

# If no Token Holder exists, just grant both admin and end user a token
if [[ $tokenStatus = "false" && $userToken = "false" ]]; then
    echo "No token holder exists. Just grant both admin and user a token"  | tee -a $tempLog
    sysadminctl -adminUser "$adminUser" -adminPassword "${adminPassword}" -secureTokenOn "$currentUser" -password "${userPass}"
    echo "Token granted to both $adminUser and end user!" | tee -a $tempLog
    
    echo "List of cryptoUsers:" | tee -a $tempLog
    diskutil apfs listcryptousers / | tee -a $tempLog
fi

# If end user is an admin Token holder while our additional admin does not have one
if [[ $userType = "Admin" && $userToken = "true" && $adminToken = "false" ]]; then
    echo "End user is an admin token holder, additional admin lacking token" | tee -a $tempLog
    sysadminctl -adminUser "$currentUser" -adminPassword "${userPass}" -secureTokenOn "$adminUser" -password "${adminPassword}"
    echo "End user admin token holder granted token to $adminUser!" | tee -a $tempLog
    
    echo "List of cryptoUsers:" | tee -a $tempLog
    diskutil apfs listcryptousers / | tee -a $tempLog
fi

# If end user is a non-admin token holder and our additional admin does not have a Token yet
if [[ $userType = "Not admin" && $userToken = "true" && $adminToken = "false" ]]; then
    echo "${currentUser} is non-admin, and admin token missing." | tee -a $tempLog
    echo "Temporarily promoting user to admin" | tee -a $tempLog
    #The only workaround to fix this is to promote the end user to admin, leverage it to manipulate the tokens and demote it again.
    #I tried it, it works and it does not harm the tokens.
    dscl . -append /groups/admin GroupMembership "$currentUser"
    echo "End user promoted to admin!" | tee -a $tempLog

    sysadminctl -adminUser "$currentUser" -adminPassword "${userPass}" -secureTokenOn "$adminUser" -password "${adminPassword}"
    echo "End user admin token holder granted token to additional admin!" | tee -a $tempLog

    echo "List of cryptoUsers:" | tee -a $tempLog
    diskutil apfs listcryptousers / | tee -a $tempLog

    dscl . -delete /groups/admin GroupMembership "$currentUser"
    echo "End user demoted back to standard!" | tee -a $tempLog
#exit 1
fi

# Leaving function commented on but it's not being called anymore. Superceeded by the earlier secure token processing
# Enables SecureToken for the currently logged in user account.
enableSecureToken() {
    sudo sysadminctl -adminUser "$adminUser" -adminPassword "${adminPassword}" -secureTokenOn "$currentUser" -password "${userPass}"
}

# Creates a PLIST containing the necessary administrator and user credentials.
echo "Creating PLIST for FileVault Enablement" | tee -a $tempLog
createPlist() {
    xmlString() {
        local xmlReturn="$1"
        xmlReturn=${xmlReturn//\&/\&amp;}
        xmlReturn=${xmlReturn//</\&lt;}
        xmlReturn=${xmlReturn//>/\&gt;}
        xmlReturn=${xmlReturn//\"/\&quot;}
        xmlReturn=${xmlReturn//\'/\&#39;}
        echo "$xmlReturn"
    }

    # destFile=${1:-/private/tmp/userToAdd.plist}  ## Keeping as code reference for argument w/default value. Commenting out to make ShellCheck happy
    destFile="/private/tmp/userToAdd.plist"

    plist=$(cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Username</key>
    <string>'%s'</string>
    <key>Password</key>
    <string>'%s'</string>
    <key>AdditionalUsers</key>
    <array>
        <dict>
            <key>Username</key>
            <string>'%s'</string>
            <key>Password</key>
            <string>'%s'</string>
        </dict>
    </array>
  </dict>
</plist>
PLIST
  )

  xmlAdminPassword=$(xmlString "$adminPassword")
  xmlUserPassword=$(xmlString "$userPass")
  
  # shellcheck disable=SC2059
  printf "$plist" "$adminUser" "$xmlAdminPassword" "$currentUser" "$xmlUserPassword" > "$destFile"
}

# Adds the currently logged in user to the list of FileVault enabled users.
addUser() {
    echo "AddUser(): Adding curren user to FV Enabled Users" | tee -a $tempLog
    fdesetup add -i < /private/tmp/userToAdd.plist
}

# Enables FileVault using a Personal Recovery Key.
enableFileVault() {
    echo "enableFileVault(): Enabling using personal recovery key" | tee -a $tempLog
    sudo -u "${currentUser}" fdesetup enable -inputplist < /private/tmp/userToAdd.plist
}

# SecureToken enabled users are automatically added to the list of Filevault enabled users when FileVault first is enabled.
# Removes the specified user(s) from the list of FileVault enabled users.
removeUser() {
    fdesetup remove -user "$userName2"
}

# Update the preboot role volume's subject directory.
updatePreboot() {
    echo "updatePreboot(): Updating preboot" | tee -a $tempLog
    diskutil apfs updatePreboot /
}

# Deletes the PLIST containing the administrator and user credentials.
cleanUp() {
    echo "cleanUp(): Deleting userToAdd.plist" | tee -a $tempLog
    rm /private/tmp/userToAdd.plist
}

#

#enableSecureToken
createPlist
if [ $fvStatus == "true" ]; then
    if [[ $fvAdminEnabled == "true" &&  $fvUserEnabled == "true" ]]; then
        echo "FileVault already enabled for both users." | tee -a $tempLog
    else
        echo "FileVault enabled, but not for all users. Adding"
        addUser
    fi
else
    echo "FileVault not yet enabled. Enabling for both users" | tee -a $tempLog
    enableFileVault
    #removeUser    ## Really what was the purpose of that one? What's this 3rd user??
fi
updatePreboot

#cleanUp
echo "We made it to the end! Deleting the temporary log because Jamf should get it now"
# Note: Not using a trap here because, if this fails, we want to know where it broke and
#       that might not make it back to jamf.
rm $tempLog
