# Reinstall configuration profile script

### ReinstallProfile.sh

This script is made for use in Jamf Pro.

It requires the ID of a configuration profile, the ID of a static group, and API credentials with the following permissions:

- Read macOS Configuration Profiles
- Read Static Computer Groups
- Update Static Computer Groups
- Read Computers

Parameter 4 is an API client ID with the above permissions

Parameter 5 is an API client secret for the ID

Parameter 6 is the ID of the configuration profile being removed and reinstalled

Parameter 7 is the ID of a static group that is in the exclusion scope for the configuration profile

#### Usage

Use this script in a Jamf Pro policy scoped to the computers you wish to remove and reinstall the specified configuration profile.


#### Order of operation

1. Check that all parameters have been provided
1. Log in to the Jamf API and get a token
1. Fetch the configuration profile and exclusion group from the Jamf API
1. Verify that the group is a static group
1. Verify that the group is in the exclusion scope for the configuration profile
1. Verify that the configuration profile is installed on the local computer
1. Fetch the computer's record from the Jamf API
1. Send a Jamf API request to add the computer to the group
1. Wait for the configuration profile to be removed locally
1. Check the configuration profile has been removed from the computer's inventory record
1. Send a Jamf API request to remove the computer from the group
1. Wait for the configuration profile to be reinstalled locally

