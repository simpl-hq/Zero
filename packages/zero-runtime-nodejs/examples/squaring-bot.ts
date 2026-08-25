import {T} from "@zero-runtime/types"
import {bot, util} from "../dist"

(async () => {
  const welcomeMessage = "Hello! I am a simple squaring bot.\n\nIf you send me a number, I will calculate its square."
  const [chat, _user, _address] = await bot.run({
    profile: {displayName: "Squaring bot example", fullName: ""},
    dbOpts: {type: "sqlite", filePrefix: "./squaring_bot"},
    options: {
      addressSettings: {autoAccept: true, welcomeMessage, businessAddress: false},
      commands: [
        {type: "command", keyword: "help", label: "Send welcome message"},
        {type: "command", keyword: "info", label: "More information (not implemented)"}
      ],
      logContacts: true,
      logNetwork: false
    },
    onMessage: async (ci, content) => {
      const n = +content.text
      const reply = typeof n === "number" && !isNaN(n)
                    ? `${n} * ${n} = ${n * n}`
                    : `this is not a number`
      await chat.apiSendTextReply(ci, reply)
    },
    onCommands: {
      "help": async (ci: T.AChatItem, _cmd: util.BotCommand) => {
        await chat.apiSendTextMessage(ci.chatInfo, welcomeMessage)
      },
      "": async (ci: T.AChatItem, _cmd: util.BotCommand) => {
        await chat.apiSendTextReply(ci, "This command is not supported")
      }
    },
    events: {
      "chatItemReaction": ({added, reaction}) => {
        console.log(`${util.senderName(reaction.chatInfo, reaction.chatReaction.chatDir)} ${added ? "added" : "removed"} reaction ${util.reactionText(reaction)}`)
      }
    },
  })
})()
