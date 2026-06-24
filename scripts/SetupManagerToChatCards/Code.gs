// Setup Manager to Chat Cards
// Code.gs
// 
// Receives a generic webhook from Jamf Setup Manager and composes
// a card for Google Chat. Sends the card via a Google Chat webhook.
//
// Fraser Hess
// © Pinnacol Assurance 2025-26
//
// Script properties:
// chatWebhookURL (required) - the webhook URL created in a Google Chat Space
// mdmURL (required) - the base URL of a Jamf Pro/School instance. Used for constructing links to computer records
// secretKeySHA512 (required) - a SHA512 of the secret key used by Jamf Setup Manager to authenticate
// ignoredSerials - a space-separated list of serial numbers to ignore and not create cards for. Useful for test computers that get provisioned often.
//
// Variables:
// dateFormatter - change the date formatter to suit your locale, time zone, and style needs

function doPost(e) {
  const chatWebhookURL = PropertiesService.getScriptProperties().getProperty('chatWebhookURL')
  const mdmURL = PropertiesService.getScriptProperties().getProperty('mdmURL')
  const secretKeySHA512 = PropertiesService.getScriptProperties().getProperty('secretKeySHA512')
  if (!chatWebhookURL || !mdmURL || !secretKeySHA512 || secretKeySHA512.length != 128) {
    return errorAndExit('Error 1: Unconfigured webapp')
  }
  const dateFormatter = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/Denver',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    timeZoneName: 'short',
  })

  // Authentication
  const clientSuppliedKey = e.parameter.key
  if (!clientSuppliedKey || !secretKeySHA512 || sha512(clientSuppliedKey) != secretKeySHA512) {
    return errorAndExit('Error 2: Failed to authenticate')
  }

  // Parse the incoming JSON payload from the request body
  let postData
  try {
    postData = JSON.parse(e.postData.contents)
  } catch (x) {
    console.error(x)
    return errorAndExit('Error 3: Unable to parse JSON')
  }
  // event key validation
  const event = postData.event
  if (event !== 'com.jamf.setupmanager.started' && event !== 'com.jamf.setupmanager.finished') {
    return errorAndExit('Error 4: Unknown event')
  }
  const finishedEventType = event == 'com.jamf.setupmanager.finished' ? true : false
  const modelName = postData.modelName
  const serialNumber = postData.serialNumber
  const computerID = postData.computerID ?? postData.jssID
  const macOSVersion = postData.macOSVersion
  const macOSBuild = postData.macOSBuild
  const setupManagerVersion = postData.setupManagerVersion
  const startedDateISO = postData.started
  const startedDate = new Date(startedDateISO)

  // The validations below are not meant to validate data from Jamf Setup Manager
  // Rather they are basic measures to prevent abuse and fuzzing
  if (!modelName || !serialNumber || !macOSVersion || !macOSBuild || !setupManagerVersion || !startedDate) {
    return errorAndExit('Error 5: Missing data')
  }

  // Data validation
  if (!/^[A-Za-z ]+$/.test(modelName) ||
    !/^[A-Z0-9]{10,12}$/.test(serialNumber) ||
    !/^[0-9\.]+$/.test(macOSVersion) ||
    !/^[0-9A-Za-z]+$/.test(macOSBuild) ||
    !/^[0-9a-z \.()]+$/.test(setupManagerVersion)) {
    return errorAndExit('Error 10: Data validation error')
  }

  const ignoredSerialsStr = PropertiesService.getScriptProperties().getProperty('ignoredSerials')
  if (ignoredSerialsStr) {
    const ignoredSerials = ignoredSerialsStr.split(' ')
    if (ignoredSerials.includes(serialNumber)) {
      return errorAndExit('Ignored serial number')
    }
  }

  var card = {
    'cardsV2': [{
      'cardId': Utilities.getUuid(),
      'card': {
        'header': {
          'title': 'Setup Manager ' + setupManagerVersion + ': Started',
          'subtitle': serialNumber + ' (' + modelName + ')'
        },
        'sections': [{
          'header': 'Details',
          'collapsible': false,
          'widgets': [{
              'decoratedText': {
                'topLabel': 'macOS',
                'text': macOSVersion + ' (' + macOSBuild + ')'
              }
            },
            {
              'decoratedText': {
                'topLabel': 'Started at',
                'text': dateFormatter.format(startedDate)
              }
            }
          ]
        }]
      }
    }]
  }

  if (finishedEventType) {
    card.cardsV2[0].card.header.title = 'Setup Manager ' + setupManagerVersion + ': Finished'
    const finishedDateISO = postData.finished
    const finishedDate = new Date(finishedDateISO)
    card.cardsV2[0].card.sections[0].widgets.push({
      'decoratedText': {
        'topLabel': 'Finished at',
        'text': dateFormatter.format(finishedDate)
      }
    })
    card.cardsV2[0].card.sections[0].widgets.push({
      'decoratedText': {
        'topLabel': 'Computer Name',
        'text': postData.computerName
      }
    })
    var userEntry = []
    for (const [key, value] of Object.entries(postData.userEntry)) {
      userEntry.push({
        'decoratedText': {
          'topLabel': 'userEntry.' + key,
          'text': value
        }
      })
    }
    if (userEntry.length > 0) {
      card.cardsV2[0].card.sections[0].widgets.push({
        'divider': {}
      })
      card.cardsV2[0].card.sections[0].widgets.push(...userEntry)
    }
    var successfulActions = []
    var failedActions = []
    for (const idx in postData.enrollmentActions) {
      if (postData.enrollmentActions[idx].status == 'finished') {
        successfulActions.push(postData.enrollmentActions[idx].label)
      } else {
        failedActions.push(postData.enrollmentActions[idx].label)
      }
    }
    if (successfulActions.length > 0) {
      card.cardsV2[0].card.sections[0].widgets.push({
        'divider': {}
      })
      card.cardsV2[0].card.sections[0].widgets.push({
        'decoratedText': {
          'topLabel': 'Successful Actions',
        }
      })
      card.cardsV2[0].card.sections[0].widgets.push({
        'textParagraph': {
          'text': successfulActions.join('<br/>'),
          'maxLines': 2
        }
      })
    }
    if (failedActions.length > 0) {
      card.cardsV2[0].card.sections[0].widgets.push({
        'divider': {}
      })
      card.cardsV2[0].card.sections[0].widgets.push({
        'decoratedText': {
          'topLabel': 'Failed Actions',
        }
      })
      card.cardsV2[0].card.sections[0].widgets.push({
        'textParagraph': {
          'text': failedActions.join('<br/>'),
          'maxLines': 2
        }
      })
    }
  }

  if (computerID) {
    var computerURL, mdm
    // if the computerID is numeric, it's probably Jamf Pro
    if (/^\d+$/.test(computerID)) {
      // Jamf Pro
      computerURL = mdmURL + '/computers.html?id=' + computerID
      mdm = "Jamf Pro"
    } else {
      // Jamf School
      computerURL = mdmURL + '/devices/details/' + computerID + '/device-list.html'
      mdm = "Jamf School"
    }
    card.cardsV2[0].card.sections[0].widgets.push({
      'buttonList': {
        'buttons': [{
          'text': 'Open Mac in ' + mdm,
          'type': 'BORDERLESS',
          'onClick': {
            'openLink': {
              'url': computerURL
            }
          }
        }]
      }
    })
  }

  const cardStr = JSON.stringify(card)
  Logger.log(cardStr)
  const options = {
    'method': 'post',
    'contentType': 'application/json',
    'payload': cardStr,
    'muteHttpExceptions': true
  }
  const response = UrlFetchApp.fetch(chatWebhookURL, options)
  const responseCode = response.getResponseCode()
  if (responseCode === 200) {
    return ContentService.createTextOutput('Data received and posted successfully').setMimeType(ContentService.MimeType.TEXT)
  } else {
    return errorAndExit('Error: Failed with HTTP ' + responseCode + ' when posting to Google Chat')
  }
}

function errorAndExit(message) {
  console.error(message)
  return ContentService.createTextOutput(message + "\n").setMimeType(ContentService.MimeType.TEXT)
}

function sha512(input) {
  // 1. Compute the digest as a byte array
  var rawHash = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_512, input);

  // 2. Convert byte array to hexadecimal string
  var txtHash = '';
  for (var i = 0; i < rawHash.length; i++) {
    var hashVal = rawHash[i];
    // Convert signed byte to unsigned (0-255)
    if (hashVal < 0) {
      hashVal += 256;
    }
    // Ensure two digits for each byte
    if (hashVal.toString(16).length == 1) {
      txtHash += '0';
    }
    txtHash += hashVal.toString(16);
  }
  return txtHash;
}