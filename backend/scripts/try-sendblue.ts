// Standalone Sendblue-bot tester — exercises the bot logic WITHOUT booting the
// DB-coupled server (no DATABASE_URL needed). Only GEMINI_API_KEY is required for
// the venue extraction; add SENDBLUE_* + `--send <number>` to actually text it.
//
//   GEMINI_API_KEY=... npx tsx scripts/try-sendblue.ts "https://www.instagram.com/reel/DXzN9wsBFRw/"
//   GEMINI_API_KEY=... SENDBLUE_API_KEY_ID=... SENDBLUE_API_SECRET=... \
//     npx tsx scripts/try-sendblue.ts "<url>" --send +8869xxxxxxxx
import {
  fetchLinkCaption,
  extractVenueFromCaption,
  formatVenueReply,
  firstUrlInText,
  SendblueClient,
} from "../src/sendblueBot.js";

const input = process.argv[2];
const sendIdx = process.argv.indexOf("--send");
const sendTo = sendIdx > -1 ? process.argv[sendIdx + 1] : undefined;

if (!input) {
  console.error('usage: npx tsx scripts/try-sendblue.ts "<url-or-text>" [--send +number]');
  process.exit(1);
}

const url = firstUrlInText(input) ?? input;
console.log("→ URL:", url);

const { caption } = await fetchLinkCaption(url);
console.log("\n→ CAPTION (first 400):\n" + (caption ? caption.slice(0, 400) : "(empty — thin/age-restricted?)"));

// Run extraction through the PRODUCTION backend proxy (which holds a working
// Gemini key) so the local tester needs no valid GEMINI_API_KEY of its own.
// Override with PROXY_BASE=... or set GEMINI_DIRECT=1 to use the direct API key.
const proxyBase = process.env.PROXY_BASE ?? "https://wanderly-api-production.up.railway.app";
async function geminiViaProxy(prompt: string): Promise<string> {
  const gs = await fetch(`${proxyBase}/v0/guest-sessions`, { method: "POST", headers: { "content-type": "application/json" } });
  const guest = ((await gs.json()) as { guest_token?: string }).guest_token ?? "";
  const r = await fetch(`${proxyBase}/v0/llm/gemini-generate-content`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-save-guest-token": guest },
    body: JSON.stringify({
      model: "gemini-3.5-flash",
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.1, maxOutputTokens: 2048, responseMimeType: "application/json" },
    }),
  });
  if (!r.ok) throw new Error(`proxy gemini ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const body = (await r.json()) as { candidates?: { content?: { parts?: { text?: string }[] } }[] };
  return body.candidates?.[0]?.content?.parts?.map((p) => p.text ?? "").join("\n").trim() ?? "";
}

const useDirect = process.env.GEMINI_DIRECT === "1";
const venue = await extractVenueFromCaption(caption, useDirect ? undefined : geminiViaProxy);
console.log("\n→ VENUE:", venue ?? "(none)");
const reply = venue ? formatVenueReply(venue) : "Couldn't find a clear place in that one.";
console.log("\n→ REPLY:\n" + reply);

if (sendTo) {
  if (!venue) {
    console.log("\n(no venue → not sending)");
  } else {
    try {
      const sbResponse = await new SendblueClient().sendMessage(sendTo, reply);
      console.log("\n✅ Sendblue accepted. Raw response:\n" + sbResponse.slice(0, 600));
      console.log("\nIf no blue bubble arrives: on the Sandbox plan Sendblue only delivers to VERIFIED contacts — add", sendTo, "as a verified contact in the Sendblue dashboard.");
    } catch (err) {
      console.log("\n❌ Sendblue send FAILED:\n" + (err instanceof Error ? err.message : String(err)));
    }
  }
}
