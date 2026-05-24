;(async function run() {
  const URL_FOR_PEER = "url-for-peer"
  const DATA_FOR_PEER = "data-for-peer"
  const PASS_DATA_TO_PEER_TEXT = "pass-data-to-peer"
  const ZERO_CHAT_COMMAND = "zero-runtime-command"
  const COPY_ZERO_CHAT_COMMAND_BTN = "copy-zero-runtime-command"
  const COMMAND_TO_PROCESS = "command-to-process"
  const PROCESS_COMMAND_BTN = "process-command"
  const urlForPeer = document.getElementById(URL_FOR_PEER)
  const dataForPeer = document.getElementById(DATA_FOR_PEER)
  const passDataToPeerText = document.getElementById(PASS_DATA_TO_PEER_TEXT)
  const zeroChatCommand = document.getElementById(ZERO_CHAT_COMMAND)
  const commandToProcess = document.getElementById(COMMAND_TO_PROCESS)
  const processCommandButton = document.getElementById(PROCESS_COMMAND_BTN)
  const copyZeroCommandButton = document.getElementById(COPY_ZERO_CHAT_COMMAND_BTN)
  copyZeroCommandButton.onclick = () => {
    navigator.clipboard.writeText(zeroChatCommand.innerText)
    if (zeroChatCommand.innerText.startsWith("/_call offer")) {
      commandToProcess.style.display = ""
      processCommandButton.style.display = ""
    }
  }
  processCommandButton.onclick = () => {
    sendCommand(JSON.parse(commandToProcess.value))
    commandToProcess.value = ""
  }
  const parsed = new URLSearchParams(document.location.hash.substring(1))
  let commandStr = parsed.get("command")
  if (commandStr) {
    await sendCommand(JSON.parse(decodeURIComponent(commandStr)))
  }

  async function sendCommand(command) {
    try {
      console.log(command)
      const {resp} = await processCommand({command})
      console.log(resp)
      switch (resp.type) {
        case "offer": {
          const {media} = command
          const {offer, iceCandidates, capabilities} = resp
          const aesKey = capabilities.encryption ? command.aesKey : undefined
          const peerWCommand = {type: "offer", offer, iceCandidates, media, aesKey, useWorker: true}
          const url = new URL(document.location)
          parsed.set("command", encodeURIComponent(JSON.stringify(peerWCommand)))
          url.hash = parsed.toString()
          urlForPeer.innerText = url.toString()
          dataForPeer.innerText = JSON.stringify(peerWCommand)

          const webRTCCallOffer = {callType: {media, capabilities}, rtcSession: {rtcSession: offer, rtcIceCandidates: iceCandidates}}
          const peerChatCommand = `/_call offer @${parsed.get("contact_id")} ${JSON.stringify(webRTCCallOffer)}`
          zeroChatCommand.innerText = peerChatCommand

          copyZeroCommandButton.style.display = ""
          return
        }
        case "answer": {
          const {answer, iceCandidates} = resp
          const peerWCommand = {type: "answer", answer, iceCandidates}
          dataForPeer.innerText = JSON.stringify(peerWCommand)

          const webRTCSession = {rtcSession: answer, rtcIceCandidates: iceCandidates}
          const peerChatCommand = `/_call answer @${parsed.get("contact_id")} ${JSON.stringify(webRTCSession)}`
          copyZeroCommandButton.style.display = ""
          zeroChatCommand.innerText = peerChatCommand
          return
        }
        case "ok":
          if ((command.type = "answer")) {
            console.log("connecting")
            commandToProcess.style.display = "none"
            processCommandButton.style.display = "none"
          }
          return
      }
    } catch (e) {
      console.log("error: ", e)
    }
  }
})()
