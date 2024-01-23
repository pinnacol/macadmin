# Cisco Secure Client scripts

## CSCRepackagePredeploy.sh and CSCRepackageWebdeploy.sh

These scripts both take Cisco Secure Client downloads as input and generate custom install disk images for an organization. Additional modules/choices are explicitly added by admin, even as Cisco includes more modules by default. VPN and Customer Experience Feedback features can be disabled.

## CSCRepackagePredeploy.sh

`CSCRepackagePredeploy.sh` takes the path to a Cisco Secure Client predeploy disk image (dmg) as a parameter. (A Cisco Secure Client predeploy image includes a macOS installer package that can install all modules.)

Example use:

```
./CSCRepackagePredeploy.sh ~/Downloads/cisco-secure-client-macos-5.1.1.42-predeploy-k9.dmg
```

The output is a customized disk image in `~/Downloads/cisco-secure-client-macos-5.1.1.42-predeploy-k9-organization.dmg`

Process overview: The source dmg is copied and modified. Cisco branding is removed. A choice changes XML file is built programmatically from valid choices in the source pkg. Only the choices specified in configuration are selected. Optionally, profiles can be added. An install script that uses the choice changes XML file is added to the disk image.

Tested on Cisco Secure Client 5.1.1.42 and 5.0.05040. (Does not work with AnyConnect 4.10.x)

## CSCRepackageWebdeploy.sh

`CSCRepackageWebdeploy.sh` takes the path to a Cisco Secure Client webdeploy package as a parameter. (A Cisco Secure Client webdeploy package is a zip file with file extension .pkg intended for use on a Cisco VPN headend to autoupdate clients as they connect to VPN. It has standalone packages for most, but not all, of the modules in CSC.)

Example use:

```
./CSCRepackageWebdeploy.sh ~/Downloads/cisco-secure-client-macos-5.1.1.42-webdeploy-k9.pkg
```

The output is a customized disk image in `~/Downloads/cisco-secure-client-macos-5.1.1.42-webdeploy-k9-organization.dmg`

Process overview: The Cisco pkg is unzipped. macOS Installer packages for each modules are found and copied. Optionally, profiles can be added. A script that installs the installer packages in the correct order is added.

Tested on Cisco Secure Client 5.1.1.42, 5.0.05040, and AnyConnect 4.10.08025.

### Configuration

Configurations are made in the scripts.

#### Organization

Set `org` to an identifier for your organization.

```
org="pinnacol"
```

#### Selected Choices (CSCRepackagePredeploy.sh)

Uncomment the `selected_choices` line and define the array of choices that will be installed

```
selected_choices=("choice_dart" "choice_secure_umbrella")
```

#### Modules (CSCRepackageWebdeploy.sh)

Uncomment the `modules` line and define the array of modules that will be installed

```
modules=("dart" "umbrella")
```

#### Fail on invalid

The default behavior is to fail if an invalid choice/module is defined. (The error thrown will list valid choices for the version provided.) This feature can be disabled.

```
fail_on_invalid=0
```

#### Disable VPN

Cisco Secure Client's core VPN functionality has to be installed, but the VPN UI can be hidden.

```
disable_vpn=1
```

#### Disable Customer Experience Feedback

```
disable_customer_experience_feedback=1
```

### Example Configuration

#### Install Umbrella only

1. Set `org` to something appropriate for your organization
1. Set `selected_choices=("choice_secure_umbrella")` for CSCRepackagePredeploy.sh or `modules=("umbrella")` for CSCRepackageWebdeploy.sh
1. Set `disable_vpn=1`
1. In the **Umbrella configuration** section, set the organizational values for organizationId, fingerprint, and userId

