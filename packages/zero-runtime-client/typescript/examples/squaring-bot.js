const {ChatClient} = require("..")
const {ChatType} = require("../dist/command")
const {ciContentText, ChatInfoType} = require("../dist/response")

run()

async function run() {
  const chat = await ChatClient.create("ws://localhost:5225")
  const user = await chat.apiGetActiveUser()
  if (!user) {
    console.log("no user profile")
    return
  }
  console.log(`Bot profile: ${user.profile.displayName} (${user.profile.fullName})`)
  const address = (await chat.apiGetUserAddress()) || (await chat.apiCreateUserAddress())
  console.log(`Bot address: ${address}`)
  await chat.enableAddressAutoAccept()
  await processMessages(chat)

  async function processMessages(chat) {
    for await (const r of chat.msgQ) {
      const resp = r instanceof Promise ? await r : r
      switch (resp.type) {
        case "contactConnected": {
          const {contact} = resp
          console.log(`${contact.profile.displayName} connected`)
          await chat.apiSendTextMessage(
            ChatType.Direct,
            contact.contactId,
            "Hello! I am a simple squaring bot - if you send me a number, I will calculate its square"
          )
          continue
        }
        case "newChatItems": {
          for (const {chatInfo, chatItem} of resp.chatItems) {
            if (chatInfo.type !== ChatInfoType.Direct) continue
            const msg = ciContentText(chatItem.content)
            if (msg) {
              const n = +msg
              const reply = typeof n === "number" && !isNaN(n) ? `${n} * ${n} = ${n * n}` : `this is not a number`
              await chat.apiSendTextMessage(ChatType.Direct, chatInfo.contact.contactId, reply)
            }
          }
        }
      }
    }
  }
}
