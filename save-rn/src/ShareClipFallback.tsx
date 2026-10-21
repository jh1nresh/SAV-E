import { Pressable, StyleSheet, Text, View } from "react-native";
import type { SharedPlaceData } from "./models";
import {
  safariOpenURL,
  shareFallbackCopy,
  usesTraditionalChinese,
} from "./inAppBrowser";

type Props = {
  href: string;
  userAgent: string;
  language: string;
  placeName?: string;
  category?: string;
  area?: string;
  sender?: string;
  note?: string | null;
  listTitle?: string;
};

export function ShareClipFallback({
  href,
  userAgent,
  language,
  placeName,
  category,
  area,
  sender,
  note,
  listTitle,
}: Props) {
  const copy = shareFallbackCopy(language);
  const zh = usesTraditionalChinese(language);
  const title = placeName || listTitle || "Savvy";
  const meta = [area, category].filter(Boolean).join(" · ");
  const sticker = heroSticker(category);

  return (
    <View style={styles.page} testID="web.clip.fallback">
      <View style={styles.hero}>
        <View style={styles.heroTop}>
          {sender ? (
            <View style={styles.chip}>
              <View style={styles.avatar}>
                <Text style={styles.avatarText}>{sender.slice(0, 1)}</Text>
              </View>
              <Text style={styles.chipText}>
                {zh ? `${sender} 分享給你` : `${sender} shared with you`}
              </Text>
            </View>
          ) : (
            <View />
          )}
          <View style={styles.plate}>
            <Text style={styles.wordmark}>Savvy</Text>
          </View>
        </View>
        <View style={styles.circle}>
          <Text style={styles.sticker}>{sticker}</Text>
        </View>
      </View>
      <View style={styles.body}>
        <Text style={styles.title}>{title}</Text>
        {meta ? <Text style={styles.meta}>{meta}</Text> : null}
        {note ? <Text style={styles.note}>{note}</Text> : null}
        <View style={styles.card}>
          <Pressable
            accessibilityRole="button"
            testID="web.clip.openSafari"
            onPress={() => {
              if (typeof window !== "undefined") {
                window.location.href = safariOpenURL(href, userAgent);
              }
            }}
            style={styles.button}
          >
            <Text style={styles.buttonText}>{copy.button}</Text>
          </Pressable>
          <Text style={styles.step}>{copy.step}</Text>
          <Text style={styles.noteMuted}>{copy.note}</Text>
        </View>
      </View>
    </View>
  );
}

export function placeArea(place?: SharedPlaceData | null): string {
  if (!place?.address) return "";
  return place.address.split(",")[0]?.trim() ?? "";
}

function heroSticker(category?: string): string {
  const value = (category ?? "").toLowerCase();
  if (value.includes("cafe") || value.includes("coffee") || value.includes("咖啡")) return "☕";
  if (value.includes("food") || value.includes("restaurant") || value.includes("餐")) return "🍜";
  return "📍";
}

const coral = "#F26B4A";
const cream = "#FFF9EB";
const ink = "#2F2E23";
const muted = "#62594F";

const styles = StyleSheet.create({
  page: { flex: 1, backgroundColor: cream },
  hero: {
    height: 300,
    backgroundColor: coral,
    paddingHorizontal: 16,
    paddingTop: 28,
    alignItems: "center",
    justifyContent: "flex-start",
  },
  heroTop: {
    width: "100%",
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "flex-start",
  },
  chip: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: cream,
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 6,
    gap: 6,
    maxWidth: "62%",
  },
  avatar: {
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: "#EADDC6",
    alignItems: "center",
    justifyContent: "center",
  },
  avatarText: { color: ink, fontWeight: "600", fontSize: 12 },
  chipText: { color: ink, fontWeight: "600", fontSize: 14, flexShrink: 1 },
  plate: {
    backgroundColor: cream,
    borderRadius: 999,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  wordmark: {
    color: "#0E4A33",
    fontSize: 22,
    fontWeight: "600",
    fontFamily: "Caveat, ui-rounded, cursive",
  },
  circle: {
    marginTop: 28,
    width: 168,
    height: 168,
    borderRadius: 84,
    backgroundColor: cream,
    alignItems: "center",
    justifyContent: "center",
  },
  sticker: { fontSize: 64 },
  body: { paddingHorizontal: 24, paddingTop: 20, paddingBottom: 32, gap: 10 },
  title: {
    color: ink,
    fontSize: 34,
    fontWeight: "600",
    fontFamily: "Caveat, 'Iansui', ui-rounded, cursive",
  },
  meta: { color: muted, fontSize: 15 },
  note: {
    color: ink,
    fontSize: 16,
    backgroundColor: "#EADDC6",
    padding: 12,
    borderRadius: 8,
  },
  card: {
    marginTop: 12,
    backgroundColor: cream,
    borderColor: "#DCCFB9",
    borderWidth: 1,
    borderRadius: 16,
    padding: 16,
    gap: 10,
  },
  button: {
    backgroundColor: coral,
    borderRadius: 27,
    minHeight: 54,
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  buttonText: {
    color: cream,
    fontSize: 17,
    fontWeight: "600",
    textAlign: "center",
  },
  step: { color: ink, fontSize: 15, textAlign: "center" },
  noteMuted: { color: muted, fontSize: 13, textAlign: "center" },
});
