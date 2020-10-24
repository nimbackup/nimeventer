import std / [
  os, asyncdispatch,
  times, uri,
  strformat, strutils, options,
  json, htmlparser, xmltree, 
  httpclient
]

import irc

type
  Config* = object
    base_url*: string
    threads_url*: string
    posts_url*: string
    reddit_url*: string
    so_tag*: string
    so_key*: string
    max_context_len*: int
    check_interval*: int
    irc_nickname*: string
    irc_password*: string
    irc_chans*: seq[string]
    irc_full_chans*: seq[string]
    telegram_ids*: seq[string]
    telegram_full_ids*: seq[string]
    discord_webhook*: string
    telegram_url*: string

var 
  config: Config
  client: AsyncIrc # IRC client instance
  allChans*: seq[string] # IRC channels to send all updates to
  allTelegramIds*: seq[string] # Telegram channels to send all updates to

proc postToDiscord(webhook, content: string) {.async.} = 
  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({"Content-Type": "application/json"})
  let data = $(
    %*{
      "username": "NimEventer", 
      "content": content
    }
  )
  let resp = await client.post(webhook, data)
  client.close()

proc postToTelegram(id, content: string) {.async.} = 
  let chan = id.encodeUrl()
  let client = newAsyncHttpClient()
  let resp = await client.get(config.telegramUrl % [chan, content.encodeUrl()])
  client.close()

proc onIrcEvent(client: AsyncIrc, event: IrcEvent) {.async.} =
  case event.typ
  of EvDisconnected, EvTimeout:
    await client.reconnect()
  else:
    discard

proc post*(content: string, disc, telegram, irc: openArray[string]) = 
  for webhook in disc:
    asyncCheck webhook.postToDiscord content
  for chan in telegram:
    asyncCheck chan.postToTelegram content
  for chan in irc:
    asyncCheck client.privmsg(chan, content)
  echo content

template catchErr*(body: untyped) =
  try:
    body
  except:
    echo "!!!!!got exception!!!!!"
    let e = getCurrentException()
    echo e.getStackTrace()
    echo e.msg
    echo "!!!!!!!!!!!!!!!!!!!!!!!"

# Nim *can* do recursive imports if you were wondering :)
import nimeventer/[nimforum, reddit, stackoverflow]

proc check {.async.} = 
  client = newAsyncIrc(
    address = "irc.freenode.net", 
    port = Port(6667),
    nick = config.ircNickname,
    serverPass = config.ircPassword,
    joinChans = allChans, 
    callback = onIrcEvent
  )
  await client.connect()

  asyncCheck client.run()
  asyncCheck doForum(config)
  asyncCheck doStackoverflow(config)
  asyncCheck doReddit(config)

proc main = 
  config = parseFile("config.json").to(Config)
  allChans = config.ircChans & config.ircFullChans
  allTelegramIds = config.telegramIds & config.telegramFullIds
  initForum()
  initStackoverflow()
  initReddit()

  asyncCheck check()
  runForever()

main()