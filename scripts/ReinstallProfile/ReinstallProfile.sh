#!/bin/bash
# ReinstallProfile.sh
# Uninstalls and reinstalls a configuration profile using an exclusion group
#
# Fraser Hess
# © Pinnacol Assurance 2024
#
# Arguments:
# $4 - API Client ID with Read macOS Configuration Profiles, Update Static Computer Groups, Read Computers, Read Static Computer Groups (required)
# $5 - API Client Secret (required)
# $6 - the ID of the configuration profile (required)
# $7 - the ID of a static group that is excluded from the configuration profile (required)

# Uncomment line below for debugging
#set -x

# Get base URL of the Jamf Pro server, removing the trailing slash
base_url=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url|sed 's/\/$//')
timeout_seconds=300

err() {
  echo "ERROR: $*" >&2
}

# Check for required arguments
client_id="${4}"
client_secret="${5}"
configuration_profile_id="${6}"
exclusion_group_id="${7}"

if [[ -z "${configuration_profile_id}" ]]; then
  err "Configuration profile ID argument is missing"
  exit 1
fi

if [[ -z "${exclusion_group_id}" ]]; then
  err "Exclusion group ID argument is missing"
  exit 1
fi

if [[ -z "${client_id}" ]]; then
  err "API Client ID argument is missing"
  exit 1
fi

if [[ -z "${client_secret}" ]]; then
  err "API Client Secret argument is missing"
  exit 1
fi


# Set up a cookie jar to handle Jamf cluster
cookie_jar=$(mktemp -t JamfWiFiProfileCookie)


# Log in to the Jamf API and store a token
if ! token=$(/usr/bin/curl -fs --request POST \
  --url "${base_url}/api/oauth/token" \
  --cookie-jar "${cookie_jar}" \
  --data-urlencode "client_id=${client_id}" \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode "client_secret=${client_secret}" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --header 'Accept: application/json' | plutil -extract access_token raw -o - -); then
  err "Error authenticating to Jamf Pro API. Check API credentials."
  exit 1
fi


# Fetch configuration profile and output name + UUID
if ! configuration_profile_record=$(/usr/bin/curl -fs --header "Authorization: Bearer ${token}" \
  --cookie "${cookie_jar}" \
  "${base_url}/JSSResource/osxconfigurationprofiles/id/${configuration_profile_id}"); then
  err "Error fetching configuration profile. Check configuration profile ID and API client permissions"
  exit 1
fi

configuration_profile_name=$(echo "${configuration_profile_record}" | /usr/bin/xmllint --xpath '/os_x_configuration_profile/general/name/text()' -)
echo "Configuration Profile Name: ${configuration_profile_name}"

configuration_profile_uuid=$(echo "${configuration_profile_record}" | /usr/bin/xmllint --xpath '/os_x_configuration_profile/general/uuid/text()' -)
echo "Configuration Profile UUID: ${configuration_profile_uuid}"


# Fetch exclusion group record and output name
if ! exclusion_group_record=$(/usr/bin/curl -fs --header "Authorization: Bearer ${token}" \
  --cookie "${cookie_jar}" \
  "${base_url}/JSSResource/computergroups/id/${exclusion_group_id}"); then
  err "Error fetching exclusion group. Check exclusion group profile ID and API client permissions"
  exit 1
fi

exclusion_group_name=$(echo "${exclusion_group_record}" | /usr/bin/xmllint --xpath '/computer_group/name/text()' -)

echo "Exclusion Group Name: ${exclusion_group_name}"
echo


# Ensure that the exclusion group is a static group
exclusion_group_smart=$(echo "${exclusion_group_record}" | /usr/bin/xmllint --xpath '/computer_group/is_smart/text()' -)

if [[ "${exclusion_group_smart}" == "true" ]]; then
  err "Exclusion group is not a static group"
  exit 1
fi


# Ensure that the exclusion group is excluded from the configuration profile
if ! configuration_profile_exclusions=$(echo "${configuration_profile_record}" | /usr/bin/xmllint \
  --xpath "/os_x_configuration_profile/scope/exclusions/computer_groups/computer_group[id=${exclusion_group_id}]" -); then
  err "Exclusion group is not excluded from configuration profile"
  exit 1
fi


# Check that the configuration profile is installed
if ! /usr/bin/profiles list | grep -q "${configuration_profile_uuid}"; then
  err "${configuration_profile_name} profile is not installed locally"
  exit 1
fi


# Lookup this computer by MAC address in the Jamf API - get ID
mac_address=$(/usr/sbin/networksetup -getmacaddress en0 | /usr/bin/awk '{ print $3 }')
if ! computer_record=$(/usr/bin/curl -fs --header "Authorization: Bearer ${token}" \
  --cookie "${cookie_jar}" \
  "${base_url}/JSSResource/computers/macaddress/${mac_address}"); then
  err "Error fetching computer record. Check API client permissions"
  exit 1
fi
 
computer_id=$(echo "${computer_record}" | /usr/bin/xmllint --xpath '/computer/general/id/text()' -)


# Send Jamf API request to add computer to exclusion group
echo "Adding computer to ${exclusion_group_name}..."
group_add_xml="<computer_group><id>${exclusion_group_id}</id><computer_additions><computer><id>${computer_id}</id></computer></computer_additions></computer_group>"

if ! /usr/bin/curl -fs --header "Authorization: Bearer ${token}" \
  --request PUT \
  --cookie "${cookie_jar}" \
  --header "Content-Type: text/xml" \
  --data "${group_add_xml}" \
  "${base_url}/JSSResource/computergroups/id/${exclusion_group_id}" > /dev/null; then
  err "Error adding computer to exclusion group. Check API client permissions"
  exit 1
fi


# Wait for configuration profile to be removed locally
echo "Waiting for ${configuration_profile_name} profile to be locally removed..."

start_time=$(date +%s)
while true; do
  if ! /usr/bin/profiles list | grep -q "${configuration_profile_uuid}"; then
    break
  fi
  sleep 10
  elapsed_time=$(( $(date +%s) - start_time ))
  if [[ ${elapsed_time} -ge ${timeout_seconds} ]]; then
    echo "Time out waiting for ${configuration_profile_name} profile to be locally removed"
    exit 1
  fi
done


# Wait for Jamf inventory to reflect that configuration profile has been removed
echo "Waiting for ${configuration_profile_name} profile to be removed from inventory..."

start_time=$(date +%s)
while true; do
  computer_record=$(/usr/bin/curl -fs --header "Authorization: Bearer ${token}" \
    --cookie "${cookie_jar}" \
    "${base_url}/JSSResource/computers/id/${computer_id}")
  if !  echo "${computer_record}" | /usr/bin/xmllint --xpath "/computer/configuration_profiles/configuration_profile[id=${configuration_profile_id}]" -; then
    break
  fi
  sleep 10
  elapsed_time=$(( $(date +%s) - start_time ))
  if [[ ${elapsed_time} -ge ${timeout_seconds} ]]; then
    err "Time out waiting for configuration profile to be removed from inventory"
    exit 1
  fi
done


# Send Jamf API request to remove computer from exclusion group
echo "Removing computer from ${exclusion_group_name}..."
group_remove_xml=$(echo "${group_add_xml}" | /usr/bin/sed 's/_additions/_deletions/g' )
/usr/bin/curl -fs --header "Authorization: Bearer ${token}" \
  --request PUT \
  --cookie "${cookie_jar}" \
  --header "Content-Type: text/xml" \
  --data "${group_remove_xml}" \
  "${base_url}/JSSResource/computergroups/id/${exclusion_group_id}" > /dev/null


# Wait for configuration profile to be observed locally
echo "Waiting for ${configuration_profile_name} profile to be reinstalled locally..."

start_time=$(date +%s)
while true; do
  if /usr/bin/profiles list | grep -q "${configuration_profile_uuid}"; then
    break
  fi
  sleep 10
  elapsed_time=$(( $(date +%s) - start_time ))
  if [[ ${elapsed_time} -ge ${timeout_seconds} ]]; then
    err "Time out waiting for configuration profile to be reinstalled locally"
    exit 1
  fi
done

echo "${configuration_profile_name} profile is reinstalled"

exit 0