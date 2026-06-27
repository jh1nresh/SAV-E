# SAV-E — App Store Listing (1.0.0)

Ready-to-paste App Store Connect metadata. Voice: warm, practical, not hypey
(see `app-store-screenshots/SAVE-App-Store-Screenshot-Design-Spec.md` §10).
Bundle `com.wanderly.app` · version `1.0.0` · build `80`.

> Char limits: App Name 30 · Subtitle 30 · Promotional Text 170 · Keywords 100 · Description 4000.

---

## English (Primary — en-US)

**App Name** (29)
```
SAV-E: Save Places from Links
```

**Subtitle** (29)
```
A private map of saved places
```

**Promotional Text** (≤170)
```
Reels, links, screenshots, a friend's text — SAV-E turns the places you mean to remember into one private map you can actually search. No public feed, no noise.
```

**Keywords** (≤100, comma-separated, no wasted spaces)
```
save places,place memory,private map,travel,restaurant list,saved spots,food map,bookmark,trip,notes
```

**Description**
```
You lose the best places. A friend sends a restaurant in a text, you save a Reel "for later," you screenshot a map link — and a month later it's all gone.

SAV-E fixes that. Paste a link, a screenshot, or a note, and SAV-E finds the real place behind it and drops it on one private map. No retyping, no copy-pasting addresses.

WHAT IT DOES
• Save from anywhere — Instagram, TikTok, Threads, 小紅書, Google or Apple Maps, a friend's message, or a plain note.
• Get the real place — SAV-E figures out the actual spot behind a messy link, with the source kept as proof.
• You confirm before it counts — uncertain clues wait in Review, so your map never fills up with wrong guesses.
• Ask your own map — "dinner tonight, walkable?" gets answered from places you already saved and trust, not the open internet.
• Build your passport — every confirmed spot becomes a private map stamp, organized by city.

PRIVATE BY DEFAULT
SAV-E is a personal notebook for places, not a social network. No feed, no followers, no public reviews. Your map is yours.

SAV-E is for the places you actually want to remember — and actually find again.
```

**What's New** (1.0.0)
```
First public release of SAV-E.

• Save places from links, screenshots, and messages onto one private map
• Review before anything counts — no wrong pins
• Ask your saved map for what's nearby and open
• Your private passport of places, by city

Thanks for trying SAV-E. Tell us what to build next.
```

---

## Traditional Chinese (zh-Hant)

**App Name** (≤30)
```
SAV-E：把連結存成地點
```

**Subtitle** (≤30)
```
你的私人地點地圖
```

**Promotional Text**
```
Reel、連結、截圖、朋友傳的訊息 —— SAV-E 把你想記住的地點變成一張可以搜尋的私人地圖。沒有公開動態，沒有雜訊。
```

**Keywords**
```
存地點,地點記憶,私人地圖,旅遊,美食地圖,收藏,餐廳清單,地圖筆記,行程,口袋名單
```

**Description**
```
好地方總是會弄丟。朋友傳了家餐廳、你存了一支「之後再看」的 Reel、截了一張地圖連結 —— 一個月後全都不見了。

SAV-E 解決這件事。貼上連結、截圖或筆記，SAV-E 會找出背後真正的地點，幫你釘在同一張私人地圖上。不用重打、不用複製貼上地址。

它能做什麼
• 從任何地方存 —— Instagram、TikTok、Threads、小紅書、Google／Apple 地圖、朋友的訊息，或一段純文字筆記。
• 找出真正的地點 —— SAV-E 從凌亂的連結認出實際的店，並保留來源當作憑證。
• 你確認過才算數 —— 不確定的線索會先進「確認」，地圖不會被錯誤的猜測塞滿。
• 直接問你的地圖 —— 「今晚走路到得了的晚餐？」由你存過、信任的地點來回答，不是整個網路。
• 累積你的護照 —— 每個確認過的地點變成一枚私人地圖章，依城市整理。

預設私密
SAV-E 是地點的私人筆記本，不是社群網路。沒有動態、沒有追蹤、沒有公開評論。你的地圖只屬於你。

SAV-E 為了那些你真的想記住、也真的想再找到的地方而生。
```

---

## Store configuration

| Field | Value |
|---|---|
| Primary category | Travel |
| Secondary category | Lifestyle |
| Price | Free |
| Age rating | 4+ (no objectionable content) |
| Privacy Policy URL | `https://sav-e.app/privacy` *(must be live before submit)* |
| Support URL | `https://sav-e.app/support` *(must be live)* |
| Marketing URL | `https://sav-e.app` *(optional)* |
| Localizations | English (US), Chinese (Traditional) |

### App Privacy (nutrition label) — data the app uses

| Service | Data type | Linked to user | Used for |
|---|---|---|---|
| Privy (sign-in) | Email / Apple / Google identifier | Yes | App Functionality, Account |
| Supabase (backend) | Saved places, reviews, profile | Yes | App Functionality |
| LocationService | Precise location | No* | App Functionality (nearby search) — not stored as identity |
| Google Places / Gemini | Search query text | No | App Functionality |

\* Confirm exact behavior against code before answering the ASC privacy form; do not over-declare.

### Screenshots to upload
From `specs/app-store-screenshots/v2/` (1242×2688 = 6.5"; also provide 6.9" if required):
`01-stop-losing-places` · `02-paste-link-real-place` · `03-confirm-before-counts` · `04-ask-your-map` · `05-passport-of-places`.
App icon: `logo-icon.png`.
