# Setup Manager To Google Chat Cards

This Google Apps Script will create Google Chat cards from Jamf Setup Manager webhooks. Setup Manager can send [webhooks](https://github.com/jamf/Setup-Manager/blob/main/Docs/Webhooks.md) at the beginning and end of its process. As of writing, none of the current webhook formats in JSM work in Google Chat. This script fixes that by ingesting a generic JSM webhook and posting formatted cards to a Google Chat space.

Insert demo image here

## Requirements

* Jamf Setup Manager 1.2 or later (1.4 or later for integration with Jamf School, 1.4.6 or later truncates the webhook URLs in logs thereby hiding any secrets)
  * use of the `jssID` or [`computerID`](https://github.com/jamf/Setup-Manager/blob/main/ConfigurationProfile.md#computerid) key in the Jamf Setup Manager configuration profile is required to create links in cards to the computer's inventory record in the MDM and is highly encouraged
* Google Workspace (It is generally assumed that organizations using Google Chat as part of Workspace also have Google Apps Script.)

## Setup

1. Create a Google Chat space or use an existing one
1. In **Apps & integrations** for the space, add a webhook. Name it 'Setup Manager' and use `https://github.com/jamf/Setup-Manager/blob/main/Images/SetupManager250.png?raw=true` as the Avatar URL. (Google Chat will cache the image.)
1. While logged in as your Google Workspace account, go to https://script.google.com in a browser
1. Create a new project, giving it an appropriate name such as 'Setup Manager to Chat Cards'
1. Paste the contents of [Code.gs](Code.gs) including the `doPost`, `errorAndExit` and `sha512` functions
1. Click on the **Project Settings** cogwheel on the left, scroll down to **Script Properties** and add the following:
   1. A `chatWebhookURL` property, copying the link from the 3 dot menu next to the webhook created in step 2 as the value
   1. An `mdmURL` property with the base URL of your Jamf instance
   1. Optionally, create an `ignoredSerials` property where the value is a space-separated list of serial numbers that cards will _not_ be posted for. (This is useful for test computers that are often wiped and re-deployed.)
1. For authentication:
   1. Generate a long, random secret key (> 30 characters) in your favorite password generator. Safe characters for a URL query string are: A-Z, a-z, 0-9, hyphen `-`, period `.`, underscore `_`, and tilde `~`.
   1. Create a SHA512 hash of the secret key:
      1. if copied to the clipboard: `pbpaste | sha512`
      1. or `echo -n iguessyougotyourhooksinme | sha512`
   1. Add a `secretKeySHA512` script property with the value of the SHA512 just hashed
1. Click the blue **Deploy** button, and click **New deployment**
1. Click the Select type cog wheel, and select Web app
1. Under _Who has access_, select Anyone.
1. Click **Deploy**

The web app will be deployed and a URL generated. e.g.
`https://script.google.com/a/macros/domain.com/s/XXXXXXXXXXX/exec`

Add the secret key generated above:

`https://script.google.com/a/macros/domain.com/s/XXXXXXXXXXX/exec?key=iguessyougotyourhooksinme`

Use this URL in a Setup Manager configuration profile. Example:

```
<key>webhooks</key>
<dict>
  <key>finished</key>
  <string>https://script.google.com/a/macros/domain.com/s/XXXXXXXXXXX/exec?key=iguessyougotyourhooksinme</string>
  <key>started</key>
  <string>https://script.google.com/a/macros/domain.com/s/XXXXXXXXXXX/exec?key=iguessyougotyourhooksinme</string>
</dict>
```

See [the JSM documentation](https://github.com/jamf/Setup-Manager/blob/main/Docs/Webhooks.md) for advanced configuration options.