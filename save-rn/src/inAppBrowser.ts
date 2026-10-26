export const clipBundleId = "com.wanderly.app.Clip";
export const smartAppBannerContent =
  `app-id=6769216556, app-clip-bundle-id=${clipBundleId}`;

export function isInAppShareBrowser(userAgent: string): boolean {
  const isIOS = /\b(iPhone|iPad|iPod)\b/i.test(userAgent)
    || (/\bMacintosh\b/i.test(userAgent) && /\bMobile\//i.test(userAgent));
  return isIOS && (/\bLine\//i.test(userAgent)
    || /\bInstagram\b/i.test(userAgent)
    || /\bMicroMessenger\b/i.test(userAgent));
}

export function isShareFallbackPath(href: string): boolean {
  try {
    const url = new URL(href);
    const first = url.pathname.split("/").filter(Boolean)[0];
    return first === "p" || first === "list";
  } catch {
    return false;
  }
}

export function usesTraditionalChinese(language: string): boolean {
  const value = language.toLowerCase();
  return value.startsWith("zh-hant")
    || value.startsWith("zh-tw")
    || value.startsWith("zh-hk")
    || value.startsWith("zh_hant")
    || value.startsWith("zh_tw")
    || value.startsWith("zh_hk");
}

export function safariOpenURL(href: string, userAgent: string): string | null {
  // Only LINE exposes the supported external-browser parameter. Other
  // webviews need their browser menu; reloading their URL cannot open Safari.
  if (!isInAppShareBrowser(userAgent) || !/\bLine\//i.test(userAgent)) return null;
  try {
    const url = new URL(href);
    if (/\bLine\//i.test(userAgent)) {
      url.searchParams.set("openExternalBrowser", "1");
    }
    return url.toString();
  } catch {
    return null;
  }
}

export function shareFallbackCopy(language: string): {
  button: string;
  step: string;
  note: string;
} {
  if (usesTraditionalChinese(language)) {
    return {
      button: "🧭 用 Safari 開啟預覽",
      step: "點右上 ⋯ → 在瀏覽器開啟",
      note: "LINE／IG／微信請改用 Safari 預覽；收藏需到完整 Savvy App 登入後確認。",
    };
  }
  return {
    button: "Open in Safari to preview",
    step: "Tap ⋯ → Open in browser",
    note: "In LINE, IG or WeChat, open Safari to preview. To save, sign in to the full Savvy App and confirm.",
  };
}

export function isGooglePhotoURL(value: string): boolean {
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase();
    if (host === "maps.googleapis.com" && url.pathname === "/maps/api/place/photo") return true;
    if (host === "places.googleapis.com" && url.pathname.includes("/media")) return true;
    return false;
  } catch {
    return value.includes("photo_reference=");
  }
}

export function publicOwnedPhotoURL(values: string[] | undefined): string | null {
  for (const value of values ?? []) {
    if (!value || isGooglePhotoURL(value)) continue;
    try {
      const url = new URL(value);
      if (url.protocol !== "http:" && url.protocol !== "https:") continue;
      if (url.username || url.password) continue;
      return url.toString();
    } catch {
      continue;
    }
  }
  return null;
}
