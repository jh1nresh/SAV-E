export const clipBundleId = "com.wanderly.app.Clip";
export const smartAppBannerContent =
  `app-id=6769216556, app-clip-bundle-id=${clipBundleId}`;

export function isInAppShareBrowser(userAgent: string): boolean {
  return /\bLine\//i.test(userAgent)
    || /\bInstagram\b/i.test(userAgent)
    || /\bMicroMessenger\b/i.test(userAgent);
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

export function safariOpenURL(href: string, userAgent: string): string {
  try {
    const url = new URL(href);
    if (/\bLine\//i.test(userAgent)) {
      url.searchParams.set("openExternalBrowser", "1");
    }
    return url.toString();
  } catch {
    return href;
  }
}

export function shareFallbackCopy(language: string): {
  button: string;
  step: string;
  note: string;
} {
  if (usesTraditionalChinese(language)) {
    return {
      button: "🧭 用 Safari 開啟，免安裝就能存",
      step: "點右上 ⋯ → 在瀏覽器開啟",
      note: "LINE／IG／微信內建瀏覽器打不開 App Clip，換 Safari 就可以",
    };
  }
  return {
    button: "Open in Safari to save, no install",
    step: "Tap ⋯ → Open in browser",
    note: "In-app browsers (LINE, IG, WeChat) can't open App Clips. Safari can.",
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
