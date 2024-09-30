#!/bin/bash
#
# Cisco Secure Client Webdeploy Repackage
# Creates a organization-specific disk image for Cisco Secure Client
# based on a webdeploy pkg (zip file) with profiles
#
# Fraser Hess
# © Pinnacol Assurance 2024
#
# Arguments:
#   $1 - path to a Cisco Secure Client webdeploy pkg
#
# Configuration

# Organization identifier
org="acme"
# Additional modules. core-vpn module is always included
# Valid modules in 5.1.1.42 are: dart, ampenabler, posture, iseposture, nvm, umbrella
#modules=("dart" "umbrella")
# choose whether or not to fail on an invalid module
fail_on_invalid=1
# Disable VPN client
disable_vpn=0
# Disable Customer Experience Feedback
disable_customer_experience_feedback=0

# Umbrella configuration. Populate to have an Umbrella OrgInfo.json created
umbrella_organizationId=""
umbrella_fingerprint=""
umbrella_userId=""
# Optional Umbrella configuration
umbrella_noNXDOMAIN="0"

# Uncomment line below for debugging
#set -x

err() {
  echo "ERROR: $*" >&2
}

if [[ -z "$1" ]]; then
  err "provide a Cisco Secure Client webdeploy pkg"
  err "$0 <path to pkg>"
  exit 1
fi

org_pkg_path="$1"

if ! /usr/bin/file -b "${org_pkg_path}" | grep -q Zip; then
  err "pkg file is not a zip or is not found"
  exit 1
fi

org_pkg_dir=$(dirname "${org_pkg_path}")
org_pkg_base=$(basename "${org_pkg_path}" .pkg)

csc_src_tmp=$(/usr/bin/mktemp -d)
csc_dst_tmp=$(/usr/bin/mktemp -d)

unzip "${org_pkg_path}" -d "${csc_src_tmp}"

if [[ ! -f "${csc_src_tmp}/VPNManifest.xml" ]]; then
  err "VPNManifest.xml not found. Check that the zip archive is a Cisco Secure Client webdeploy file"
  exit 1
fi


# Copy module pkgs
mount_point=$(/usr/bin/mktemp -d)

modules=("core-vpn" "${modules[@]}")

for mod in "${modules[@]}"; do
  if [[ "${mod}" == "core-vpn" ]]; then
    dmg_rel_path=$(/usr/bin/xmllint --xpath "/vpn/file[@is_core='yes']/uri/text()" "${csc_src_tmp}/VPNManifest.xml")
  else
    dmg_rel_path=$(/usr/bin/xmllint --xpath "/vpn/file[@module='${mod}']/uri/text()" "${csc_src_tmp}/VPNManifest.xml")
  fi
  if [[ ${fail_on_invalid} -eq 1 && ! -f "${csc_src_tmp}/${dmg_rel_path}" ]]; then
    err "invalid module: $mod"
    exit 1
  fi
  if ! /usr/bin/hdiutil attach -nobrowse -mountpoint "${mount_point}" "${csc_src_tmp}/${dmg_rel_path}"; then
    err "failed to mount ${csc_src_tmp}/${dmg_rel_path}"
    exit 1
  fi
  cp "${mount_point}"/*.pkg "${csc_dst_tmp}"
  hdiutil detach "${mount_point}"
done


# Create Profiles folder structure
/bin/mkdir -p "${csc_dst_tmp}/Profiles/vpn" "${csc_dst_tmp}/Profiles/ampenabler" "${csc_dst_tmp}/Profiles/feedback" \
"${csc_dst_tmp}/Profiles/iseposture" "${csc_dst_tmp}/Profiles/nvm" "${csc_dst_tmp}/Profiles/umbrella"


# Create ACTransforms.xml
cat > "${csc_dst_tmp}/Profiles/ACTransforms.xml" << EOF
<!-- Optional AnyConnect installer settings are provided below. Uncomment the setting(s) to perform optional action(s) at install time.  -->
<Transforms>
    <!-- <DisableVPN>true</DisableVPN> -->
    <!-- <DisableCustomerExperienceFeedback>true</DisableCustomerExperienceFeedback> -->
</Transforms>
EOF


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
  uncommentXML "${csc_dst_tmp}/Profiles/ACTransforms.xml" "DisableVPN"
fi

# Disable Customer Experience Feedback
if [[ ${disable_customer_experience_feedback} -eq 1 ]]; then
  uncommentXML "${csc_dst_tmp}/Profiles/ACTransforms.xml" "DisableCustomerExperienceFeedback"
fi


# Umbrella Profile
# Set organizational values for organizationId, fingerprint, and userId
if [[ -n "${umbrella_organizationId}" && -n "${umbrella_fingerprint}" && -n "${umbrella_userId}" ]]; then
  orginfo_path="${csc_dst_tmp}/Profiles/umbrella/OrgInfo.json"
  cat > "${orginfo_path}" << EOF
{
    "organizationId" : "${umbrella_organizationId}",
    "fingerprint" : "${umbrella_fingerprint}",
    "userId" : "${umbrella_userId}"
}
EOF

  if [[ "${umbrella_noNXDOMAIN}" == "1" ]]; then
    /usr/bin/plutil -insert noNXDOMAIN -string 1 -r "${orginfo_path}"
  fi

fi


# Uncomment section below to add VPN Profiles to disk image
# change profile-name to match filename and paste profile before EOF
#cat > "${csc_dst_tmp}/Profiles/vpn/profile-name.xml" << EOF

#EOF


# Add install script
cat > "${csc_dst_tmp}/InstallCiscoSecureClient-${org}.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")" || exit 1
core_vpn_pkg=\$(find . -name '*core-vpn*.pkg')
/usr/sbin/installer -target / -pkg "\$core_vpn_pkg"
other_pkgs=\$(find . -name '*.pkg' ! -name '*core-vpn*.pkg')
for pkg in \$other_pkgs; do
  /usr/sbin/installer -target / -pkg "\$pkg"
done
EOF

/bin/chmod 755 "${csc_dst_tmp}/InstallCiscoSecureClient-${org}.sh"

# Debug step
#open ${csc_dst_tmp}


# Create compressed read-only organizational disk image
org_dmg_path="${org_pkg_dir}/${org_pkg_base}-${org}.dmg"

if ! /usr/bin/hdiutil create -fs HFS+ -format UDZO -volname "${org_pkg_base}-${org}" -srcfolder "${csc_dst_tmp}" "${org_dmg_path}" ; then
  err "failed to create organizational disk image"
  exit 1
fi

echo "New disk image at: ${org_dmg_path}"
