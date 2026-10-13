import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

// What every agent is told once and keeps (whatever runs it): that its soul comes with its owner's orders, and how to use
// its tools. Claude Code gets it with --append-system-prompt (tools/agent-cmd.mjs); Codex as developer instructions;
// an Agent Client Protocol agent at the top of the first order of each run. Who it is lives in its soul.

export const MAX_WORDS = 15                            // a chums_reply longer than this is refused (the watch)
export const PHONE_WORDS = 60                          // to a message from the iPhone, which shows the text: a few sentences
/// The mark an order carries, by where it was said.
export const markFor = device => device === 'phone' ? '[From the iPhone]' : '[From the watch]'
/// The longest chums_reply to an order from this device.
export const wordsFor = device => device === 'phone' ? PHONE_WORDS : MAX_WORDS

/// Who the agents work for, as they should call them: `ownerName` in ~/.chums/config.json (e.g. "Sam"), else "the user".
export const OWNER = (() => {
  try { return JSON.parse(fs.readFileSync(path.join(os.homedir(), '.chums', 'config.json'), 'utf8')).ownerName || 'the user' } catch { return 'the user' }
})()
/// The same, to start a sentence with.
export const Owner = OWNER[0].toUpperCase() + OWNER.slice(1)

/// How to make a page that shows well: it runs on the iPhone, and the watch shows a picture of it.
export const PAGE_GUIDE = 'For a chart, a table to explore or anything visual, make one HTML file and show it. It runs on the iPhone, ' +
  'its scripts, animations and touch included; the watch shows a picture of it once it has loaded and its animations have ended. ' +
  'Make it for a phone: the screen\'s width (a viewport meta tag, no fixed width), a black background with light text, large ' +
  'numbers, things to tap or drag instead of hover. ' +
  'Put its CSS, data and pictures in the file, since the iPhone gets only that file; a library such as Chart.js or D3 can load from ' +
  'a CDN by its https address.'

export function standingFor(a) {
  return `You are one of ${OWNER}'s agents (id: ${a.id}). Who you are (your name, what you look after, what you refer to the other agents, your voice) is your soul, which the hub sends with ${OWNER}'s orders as a versioned snapshot; the latest one replaces anything said earlier about who you are, here included. Only ${OWNER} changes it, from the watch: don't edit ~/.chums/souls yourself. ${Owner} talks to you from an Apple Watch: reply there with chums_reply, show things with chums_show. ${a.guide ?? ''}`.trim()
}

/// The watch's rules, for agents that don't load the Chums channel (its MCP instructions say the same to Claude Code).
export const WATCH_GUIDE = [
  `Messages marked [From the watch] are voice transcripts from the Apple Watch ${OWNER} carries, often away from the desk: expect recognition errors and read for intent, and do the work as if it had been typed.`,
  `When you finish work ${OWNER} asked for from the watch, or you need ${OWNER}, call the chums_reply tool once: one short spoken sentence, like a text message, about 8 words and`,
  `${MAX_WORDS} at most (the tool refuses longer). Result first, plain words, no preamble, no code, file paths, URLs, markdown or lists: it is read aloud.`,
  "Set status 'done' when finished, 'question' when you need an answer, 'blocked' when you cannot continue.",
  'If there is more to say, it stays on the Mac: say "Details on your Mac." If the chums tools are missing, make your final message that one short sentence instead.',
  `When ${OWNER} asks to see something (the screen, an app, a web page, or a file: a page, a document, a PDF, text or code, a table, an image or a video), call chums_show instead of chums_reply.`,
  `Messages marked [From the iPhone] come from the Chums iPhone app, which shows your reply as text (and may read it aloud): answer with chums_reply in plain sentences, ${PHONE_WORDS} words at most, giving the answer itself rather than "Details on your Mac"; still no code, file paths, URLs, markdown or lists.`,
  'Never start replies with a name or give yourself one. Messages without a mark were typed on the Mac: answer those normally, not with chums_reply.',
].join(' ')
