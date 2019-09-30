#! /usr/bin/python

# Pulls the provisioned computer name from inventory preload "barcode2" field and sets the computer name
# If "barcode2" is null, will set the computer name to "assetTag" If both null, will fail.
#
# Note: Written in Python2 using urllib2 because that's what's pre-installed on the Macs prior to Catalina
#
## Arguments:
## 4th argument (from Jamf): b64encoded username+password of an api account with readOnly permissions for inventory, computer
# Do encoding with:
## from base64 import b64encode
## b64encode(("%s:%s" % ( api_username, api_password )).encode('ascii')).decode("ascii")
# Use a purpose-built account with only "read" permissions for "computers" and "Inventory Preload objects" ex: api-computerReadOnly
#
# By Len Krygsman IV, Devoted Health 2019


### Jamf Server to use:
jamfRoot = "<myCorp>.jamfcloud.com"

import json
import os
import sys
import urllib2

# Get the b64encoded api user & password from the 4th argument
b64userAndPass = sys.argv[4]

getInventoryPreloadURL = "https://" + jamfRoot + "/uapi/inventory-preload?page=0&pagesize=100&sort=ASC&sortBy=id"

def getAuthHeader ( b64userAndPass ):
  '''
  Get an API token from Jamf. The token doesn't last long, but this process is short enough we don't care.
  Takes in a b64 encoded username and password of a user with read permissions on Inventory and Computer objects
  Returns the full header needed for the main API query
  DO NOT USE AN ADMIN ACCOUNT FOR THIS.
  '''
  tokensUrl = "https://" + jamfRoot + "/uapi/auth/tokens"
  basicHeaders = { 'Authorization' : 'Basic %s' % b64userAndPass }

  req = urllib2.Request( tokensUrl, "", basicHeaders )  ## Need to push a blank "data" to make it POST
  response = urllib2.urlopen(req)
  tokenRequest = json.loads(response.read())

  if response.code != 200:
    print "Auth-Token failed! " + response.msg
    sys.exit(1)

  auth = "Bearer %s" % tokenRequest['token']
  fullHeader = { 'Accept' : 'application/json' , 'Content-Type' : 'application/json' , 'Authorization' : auth }
  return fullHeader

# Do the API call to GET the full preloaded inventory
header = getAuthHeader ( b64userAndPass )
ipReq = urllib2.Request ( getInventoryPreloadURL, headers=header )
ipResult = urllib2.urlopen(ipReq)

if ipResult.code != 200:
  print "Inventory Preload request failed! " + ipResult.msg
  sys.exit(2)
inventoryReturn = json.loads(ipResult.read())

inventory = dict([ (d['serialNumber'], d) for d in inventoryReturn["results"] ])

# Determine the serial number of this machine
command = "ioreg -l | awk '/IOPlatformSerialNumber/ { print $4;}'"
serial = os.popen(command).read().split('"' , 2)[1]
newComputerName = ''

# Get the new computer name from the barCode2 field, if available, or the assetTag field
if 'barCode2' in inventory[serial]:
  newComputerName = inventory[serial].get('barCode2')
elif 'assetTag' in inventory[serial]:
  newComputerName = inventory[serial].get('assetTag')
else:
  print ("ERROR: No barcode2 set or assetTag number to fall back on")
  sys.exit(2)

# Echo out the new computer name for the sake of logging in the Jamf console
print ( newComputerName )

# Form and run the shell commands to set the new computer name
rename1 = 'scutil --set ComputerName "' + newComputerName + '"'
rename2 = 'scutil --set LocalHostName "' + newComputerName + '"'
rename3 = 'scutil --set HostName "' + newComputerName + '"'

renameResult1 = os.popen(rename1).close()
renameResult2 = os.popen(rename2).close()
renameResult3 = os.popen(rename3).close()

# Verify they all succeeded. If they didn't, squak (will get picked up by the Jamf console)
if ( renameResult1 is None) and ( renameResult2 is None) and ( renameResult3 is None):
  print "Successfully renamed to " + newComputerName
else:
  if renameResult1 is not None:
    print "Setting ComputerName Failed! Exit Code " + str(os.WEXITSTATUS(renameResult1))
  if renameResult2 is not None:
    print "Setting LocalHostName Failed! Exit Code " + str(os.WEXITSTATUS(renameResult2))
  if renameResult3 is not None:
    print "Setting HostName Failed! Exit Code "  + str(os.WEXITSTATUS(renameResult2))

print "Running Jamf Inventory to submit new name"
os.popen('jamf recon').close()
