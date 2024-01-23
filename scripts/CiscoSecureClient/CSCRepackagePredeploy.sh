#!/bin/bash
#
# Cisco Secure Client Predeploy Repackage
# Creates a organization-specific disk image for Cisco Secure Client
# based on a predeploy dmg with profiles, and a choices xml file for installer(8)
#
# Fraser Hess
# © Pinnacol Assurance 2023-2024
#
# Arguments:
#   $1 - path to a Cisco Secure Client predeploy dmg
#
# Configuration

# Organization identifier
org="acme"
# Additional choices. choice_anyconnect_vpn is always included
# Valid choices in 5.1.1.42 are:
# choice_fireamp, choice_dart, choice_secure_firewall_posture, choice_iseposture,
# choice_nvm, choice_secure_umbrella, choice_thousandeyes, choice_duo, choice_zta
#selected_choices=("choice_dart" "choice_secure_umbrella")
# choose whether or not to fail on an invalid choice
fail_on_invalid=1
# Disable VPN client
disable_vpn=0
# Disable Customer Experience Feedback
disable_customer_experience_feedback=0

# Umbrella configuration. Populate to have an Umbrella OrgInfo.json created
umbrella_organizationId=""
umbrella_fingerprint=""
umbrella_userId=""

# Uncomment line below for debugging
#set -x

err() {
  echo "ERROR: $*" >&2
}

if [[ -z "$1" ]]; then
  err "provide a Cisco Secure Client predeploy dmg"
  err "$0 <path to dmg>"
  exit 1
fi

csc_dmg_path="$1"

if ! /usr/bin/file -b "${csc_dmg_path}" | grep -q zlib; then
  err "dmg file is in an unexpected format or is not found"
  exit 1
fi

org_dmg_dir=$(dirname "${csc_dmg_path}")
org_dmg_base=$(basename "${csc_dmg_path}" .dmg)
rw_dmg_path="${org_dmg_dir}/${org_dmg_base}-rw.dmg"

# Make a read-write disk image
if ! /usr/bin/hdiutil convert "${csc_dmg_path}" -format UDRW -o "${rw_dmg_path}"; then
  err "failed to create read-write disk image"
  exit 1
fi


# Mount the read-write disk image
mount_point=$(/usr/bin/mktemp -d)
/usr/bin/hdiutil attach -nobrowse -mountpoint "${mount_point}" "${rw_dmg_path}"


# Remove Cisco branding
/bin/rm -rf "${mount_point}/.VolumeIcon.icns"
/bin/rm -rf "${mount_point}/.background"
/bin/rm -rf "${mount_point}/.DS_Store"


# Rename volume
/usr/sbin/diskutil rename "${mount_point}" "$(/usr/sbin/diskutil info -plist "${mount_point}" | plutil -extract VolumeName raw -) ${org}"


# Build choice changes XML
choices=$(/usr/sbin/installer -showChoiceChangesXML -pkg "${mount_point}/Cisco Secure Client.pkg" | /usr/bin/xmllint --xpath 'plist/array/dict[string="selected"]/key[contains(text(),"choiceIdentifier")]/following-sibling::string/text()' -)

## Check for invalid choices
selected_choices=("choice_anyconnect_vpn" "${selected_choices[@]}")

if [[ ${fail_on_invalid} -eq 1 ]]; then
  for potential_choice in "${selected_choices[@]}"; do
    if ! echo "${choices}" | grep -Eq "^${potential_choice}\$"; then
      err "invalid choice: ${potential_choice}"
      printf "Valid choices:\n%s" "${choices}"
      /usr/bin/hdiutil detach "${mount_point}"
      /bin/rm "${rw_dmg_path}"
      exit 1
    fi
  done
fi

choices_path="${mount_point}/CiscoSecureClientChoices.xml"

IFS=$'\n' read -rd '' -a choices_array <<< "${choices}"

cat > "${choices_path}" << EOF 
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array/>
</plist>
EOF

for i in "${!choices_array[@]}"; do
  selected=0
  for choice in "${selected_choices[@]}"; do
    if [[ "${choice}" == "${choices_array[${i}]}" ]]; then
      selected=1
      break
    fi
  done
  /usr/libexec/PlistBuddy -c "Add : dict" "${choices_path}"
  /usr/libexec/PlistBuddy -c "Add :${i}:attributeSetting integer ${selected}" "${choices_path}"
  /usr/libexec/PlistBuddy -c "Add :${i}:choiceAttribute string selected" "${choices_path}"
  /usr/libexec/PlistBuddy -c "Add :${i}:choiceIdentifier string ${choices_array[${i}]}" "${choices_path}"
done


uncommentXML() {
path="${1}"
content="${2}"
read -r -d '' stylesheet << EOF
<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  <xsl:template match="node() | @*">
    <xsl:copy>
      <xsl:apply-templates select="node() | @*"/>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="comment()[contains(., '${content}')]">
    <xsl:value-of select="normalize-space(.)" disable-output-escaping="yes"/>
  </xsl:template>
</xsl:stylesheet>
EOF
cp "${path}" "${path}.orig"
/usr/bin/xsltproc <(echo "${stylesheet}") "${path}.orig" > "${path}"
}

# Disable VPN
if [[ ${disable_vpn} -eq 1 ]]; then
  uncommentXML "${mount_point}/Profiles/ACTransforms.xml" "DisableVPN"
fi

# Disable Customer Experience Feedback
if [[ ${disable_customer_experience_feedback} -eq 1 ]]; then
  uncommentXML "${mount_point}/Profiles/ACTransforms.xml" "DisableCustomerExperienceFeedback"
fi


# Umbrella Profile
# Set organizational values for organizationId, fingerprint, and userId
if [[ -n "${umbrella_organizationId}" && -n "${umbrella_fingerprint}" && -n "${umbrella_userId}" ]]; then
cat > "${mount_point}/Profiles/umbrella/OrgInfo.json" << EOF
{
    "organizationId" : "${umbrella_organizationId}",
    "fingerprint" : "${umbrella_fingerprint}",
    "userId" : "${umbrella_userId}"
}
EOF
fi


# VPN Profile
# Uncomment section below to add VPN Profiles to disk image
# change profile-name to match filename and paste profile before EOF
#cat > "${mount_point}/Profiles/vpn/profile-name.xml" << EOF

#EOF


# Add install script to disk image
cat > "${mount_point}/InstallCiscoSecureClient-${org}.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")" || exit 1
/usr/sbin/installer -target / -pkg "Cisco Secure Client.pkg" -applyChoiceChangesXML CiscoSecureClientChoices.xml 
EOF

/bin/chmod 755 "${mount_point}/InstallCiscoSecureClient-${org}.sh"


# Unmount read-write disk image
/usr/bin/hdiutil detach "${mount_point}"


# Create compressed read-only organizational disk image
org_dmg_path="${org_dmg_dir}/${org_dmg_base}-${org}.dmg"

if ! /usr/bin/hdiutil convert "${rw_dmg_path}" -format UDZO -o "${org_dmg_path}"; then
  err "failed to create organizational disk image"
  exit 1
fi

echo "New disk image at: ${org_dmg_path}"
