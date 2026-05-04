import AsyncStorage from "@react-native-async-storage/async-storage";
import * as Clipboard from "expo-clipboard";
import { StatusBar } from "expo-status-bar";
import { useEffect, useMemo, useState } from "react";
import {
  Alert,
  Linking,
  Pressable,
  SafeAreaView,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { demoPlaces } from "./src/demoData";
import { parseSharedLink } from "./src/importLink";
import {
  categoryLabel,
  Place,
  PlaceCategory,
  SharedTripData,
  statusLabel,
} from "./src/models";
import {
  buildAppleMapsUrl,
  buildSharedTripData,
  buildTripLink,
  decodeTripLink,
} from "./src/sharedTrip";

type TabKey = "places" | "trip" | "share";

const allCategories: Array<PlaceCategory | "all"> = [
  "all",
  "food",
  "cafe",
  "bar",
  "attraction",
  "stay",
  "shopping",
];

const storageKey = "@wanderly-rn/bookmarks";

export default function App() {
  const [activeTab, setActiveTab] = useState<TabKey>("places");
  const [activeCategory, setActiveCategory] = useState<PlaceCategory | "all">("all");
  const [tripName, setTripName] = useState("Weekend Drive");
  const [tripCity, setTripCity] = useState("Miami");
  const [bookmarks, setBookmarks] = useState<Place[]>([]);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [importLink, setImportLink] = useState("");
  const [importMessage, setImportMessage] = useState("");
  const [pendingImport, setPendingImport] = useState<Place | null>(null);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    void loadBookmarks();
  }, []);

  const visiblePlaces = useMemo(
    () =>
      activeCategory === "all"
        ? bookmarks
        : bookmarks.filter((place) => place.category === activeCategory),
    [activeCategory, bookmarks]
  );

  const selectedPlaces = useMemo(
    () => bookmarks.filter((place) => selectedIds.includes(place.id)),
    [bookmarks, selectedIds]
  );

  const tripData = buildSharedTripData(tripName, tripCity, selectedPlaces);
  const tripLink = buildTripLink(tripData);
  const decodedTrip = decodeTripLink(tripLink);
  const nextStop = selectedPlaces[0];
  const importedCount = Math.max(bookmarks.length - demoPlaces.length, 0);

  async function loadBookmarks() {
    try {
      const raw = await AsyncStorage.getItem(storageKey);
      const loaded = raw ? ((JSON.parse(raw) as Place[]) ?? demoPlaces) : demoPlaces;
      setBookmarks(loaded);
      setSelectedIds((current) =>
        current.length > 0 ? current.filter((id) => loaded.some((place) => place.id === id)) : defaultSelectedIds(loaded)
      );
    } catch {
      setBookmarks(demoPlaces);
      setSelectedIds(defaultSelectedIds(demoPlaces));
    } finally {
      setIsReady(true);
    }
  }

  async function persistBookmarks(next: Place[]) {
    setBookmarks(next);
    await AsyncStorage.setItem(storageKey, JSON.stringify(next));
  }

  function togglePlace(placeId: string) {
    setSelectedIds((current) =>
      current.includes(placeId) ? current.filter((id) => id !== placeId) : [...current, placeId]
    );
  }

  async function importSharedLink() {
    await handleImportedLink(importLink);
  }

  async function importFromClipboard() {
    const clipboardText = (await Clipboard.getStringAsync()).trim();
    if (!clipboardText) {
      Alert.alert("Clipboard is empty", "Copy a place or event link first.");
      return;
    }
    setImportLink(clipboardText);
    await handleImportedLink(clipboardText);
  }

  async function handleImportedLink(rawLink: string) {
    const parsed = parseSharedLink(rawLink);
    if (!parsed) {
      Alert.alert("Unsupported link", "Paste a Google Maps, Apple Maps, Luma, or normal place link.");
      return;
    }

    const duplicate = bookmarks.find(
      (place) =>
        (parsed.sourceUrl && place.sourceUrl === parsed.sourceUrl) ||
        (place.name.toLowerCase() === parsed.name.toLowerCase() &&
          place.address.toLowerCase() === parsed.address.toLowerCase())
    );

    if (duplicate) {
      setImportMessage(`Already saved: ${duplicate.name}`);
      setPendingImport(null);
      setSelectedIds((current) => (current.includes(duplicate.id) ? current : [duplicate.id, ...current]));
      setImportLink("");
      return;
    }

    if (parsed.importKind === "event") {
      setPendingImport(parsed);
      setImportMessage(`Refine event stop: ${parsed.eventLabel ?? parsed.name}`);
      return;
    }

    await saveBookmark(parsed, `Saved to bookmarks: ${parsed.name}`);
  }

  async function saveBookmark(place: Place, message?: string) {
    const next = [place, ...bookmarks];
    await persistBookmarks(next);
    setPendingImport(null);
    setSelectedIds((current) => [place.id, ...current.filter((id) => id !== place.id)]);
    setImportMessage(message ?? `Saved to bookmarks: ${place.name}`);
    setImportLink("");
  }

  async function saveRefinedImport() {
    if (!pendingImport) return;
    await saveBookmark(pendingImport, `Saved refined stop: ${pendingImport.name}`);
  }

  function updatePendingImport<K extends keyof Place>(key: K, value: Place[K]) {
    setPendingImport((current) => (current ? { ...current, [key]: value } : current));
  }

  function dismissPendingImport() {
    setPendingImport(null);
    setImportMessage("");
  }

  async function shareTripLink() {
    await Share.share({
      message: `Wanderly trip: ${tripLink}`,
      url: tripLink,
    });
  }

  async function shareTeslaHandoff() {
    if (!nextStop) {
      Alert.alert("No stop selected", "Add at least one bookmark to the trip first.");
      return;
    }

    const appleMapsUrl = buildAppleMapsUrl(nextStop);
    const summary = [
      `Wanderly trip: ${tripName}`,
      `Next stop: ${nextStop.name}`,
      nextStop.address,
      appleMapsUrl,
    ].join("\n");

    await Share.share({
      message: summary,
      url: appleMapsUrl,
    });
  }

  async function openTripLink() {
    await Linking.openURL(tripLink);
  }

  if (!isReady) {
    return (
      <SafeAreaView style={styles.safeArea}>
        <View style={styles.loadingWrap}>
          <Text style={styles.loadingText}>Loading bookmarks...</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <View style={styles.appShell}>
        <View style={styles.header}>
          <Text style={styles.brand}>Wanderly</Text>
          <Text style={styles.subtitle}>
            Save places, refine event stops, and turn bookmarks into a trip you can share or hand off.
          </Text>
        </View>

        <View style={styles.tabRow}>
          <TabButton label="Places" active={activeTab === "places"} onPress={() => setActiveTab("places")} />
          <TabButton label="Trip" active={activeTab === "trip"} onPress={() => setActiveTab("trip")} />
          <TabButton label="Share" active={activeTab === "share"} onPress={() => setActiveTab("share")} />
        </View>

        <ScrollView contentContainerStyle={styles.content}>
          {activeTab === "places" ? (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Bookmarks</Text>

              <View style={styles.card}>
                <Text style={styles.cardTitle}>Import a place or event link</Text>
                <LabeledInput
                  label="Paste link"
                  value={importLink}
                  onChangeText={setImportLink}
                  multiline
                  placeholder="https://maps.google.com/... or https://lu.ma/..."
                />
                <View style={styles.inlineActionRow}>
                  <ActionButton label="Import from Clipboard" onPress={importFromClipboard} tone="secondary" compact />
                  <ActionButton label="Save to Bookmarks" onPress={importSharedLink} compact />
                </View>
                <Text style={styles.helperText}>
                  Current support: Google Maps, Apple Maps, Luma, and generic links with safe fallback parsing.
                </Text>
                {importMessage ? <Text style={styles.successText}>{importMessage}</Text> : null}
              </View>

              {pendingImport ? (
                <View style={styles.card}>
                  <Text style={styles.cardTitle}>Refine imported event stop</Text>
                  {pendingImport.eventLabel ? (
                    <Text style={styles.helperText}>Event: {pendingImport.eventLabel}</Text>
                  ) : null}
                  <LabeledInput
                    label="Venue / stop name"
                    value={pendingImport.name}
                    onChangeText={(text) => updatePendingImport("name", text)}
                  />
                  <LabeledInput
                    label="Address"
                    value={pendingImport.address}
                    onChangeText={(text) => updatePendingImport("address", text)}
                  />
                  <Text style={styles.inputLabel}>Category</Text>
                  <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.filterRow}>
                    {allCategories
                      .filter((category): category is PlaceCategory => category !== "all")
                      .map((category) => (
                        <Chip
                          key={category}
                          label={categoryLabel[category]}
                          active={pendingImport.category === category}
                          onPress={() => updatePendingImport("category", category)}
                        />
                      ))}
                  </ScrollView>
                  <LabeledInput
                    label="Planner note"
                    value={pendingImport.note ?? ""}
                    onChangeText={(text) => updatePendingImport("note", text)}
                    multiline
                    placeholder="Add venue details, meetup note, or arrival context"
                  />
                  <View style={styles.inlineActionRow}>
                    <ActionButton label="Dismiss" onPress={dismissPendingImport} tone="secondary" compact />
                    <ActionButton label="Save Refined Stop" onPress={saveRefinedImport} compact />
                  </View>
                </View>
              ) : null}

              <View style={styles.summaryRow}>
                <SummaryPill label={`${bookmarks.length} bookmarks`} />
                <SummaryPill label={`${importedCount} imported`} />
                <SummaryPill label={`${selectedPlaces.length} in trip`} />
              </View>

              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.filterRow}>
                {allCategories.map((category) => (
                  <Chip
                    key={category}
                    label={category === "all" ? "All" : categoryLabel[category]}
                    active={activeCategory === category}
                    onPress={() => setActiveCategory(category)}
                  />
                ))}
              </ScrollView>

              {visiblePlaces.map((place) => (
                <PlaceCard
                  key={place.id}
                  place={place}
                  selected={selectedIds.includes(place.id)}
                  onToggle={() => togglePlace(place.id)}
                />
              ))}
            </View>
          ) : null}

          {activeTab === "trip" ? (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Trip planner</Text>
              <View style={styles.card}>
                <LabeledInput label="Trip name" value={tripName} onChangeText={setTripName} />
                <LabeledInput label="City" value={tripCity} onChangeText={setTripCity} />
                <Text style={styles.helperText}>
                  This matches the native Wanderly model: bookmarks first, trip assembly second.
                </Text>
              </View>

              <View style={styles.card}>
                <Text style={styles.cardTitle}>Stops</Text>
                {selectedPlaces.length === 0 ? (
                  <Text style={styles.emptyText}>Add bookmarks from the Places tab.</Text>
                ) : (
                  selectedPlaces.map((place, index) => (
                    <View key={place.id} style={styles.stopRow}>
                      <View style={styles.stopIndex}>
                        <Text style={styles.stopIndexText}>{index + 1}</Text>
                      </View>
                      <View style={styles.stopBody}>
                        <Text style={styles.stopName}>{place.name}</Text>
                        <Text style={styles.stopMeta}>{place.address}</Text>
                        <Text style={styles.stopMeta}>
                          {categoryLabel[place.category]} · {statusLabel[place.status]}
                        </Text>
                      </View>
                    </View>
                  ))
                )}
              </View>

              <View style={styles.card}>
                <Text style={styles.cardTitle}>Trip link</Text>
                <Text style={styles.codeBlock}>{tripLink}</Text>
                <ActionButton label="Share Wanderly Trip Link" onPress={shareTripLink} />
                <ActionButton label="Open Trip Link" onPress={openTripLink} tone="secondary" />
              </View>
            </View>
          ) : null}

          {activeTab === "share" ? (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Tesla handoff</Text>

              <View style={styles.card}>
                <Text style={styles.cardTitle}>Share summary</Text>
                <Text style={styles.previewHeadline}>{tripName}</Text>
                <Text style={styles.previewSubhead}>{tripCity || "No city set"}</Text>
                <Text style={styles.helperText}>
                  Share the trip link with friends, then send the first stop to Tesla as a clean navigation handoff.
                </Text>
              </View>

              <View style={styles.card}>
                <Text style={styles.cardTitle}>Next stop</Text>
                {nextStop ? (
                  <View style={styles.nextStopCard}>
                    <Text style={styles.stopName}>{nextStop.name}</Text>
                    <Text style={styles.stopMeta}>{nextStop.address}</Text>
                    <Text style={styles.stopMeta}>
                      {categoryLabel[nextStop.category]} · via {nextStop.sourcePlatform}
                    </Text>
                    <ActionButton label="Send Next Stop to Tesla" onPress={shareTeslaHandoff} />
                  </View>
                ) : (
                  <Text style={styles.emptyText}>Add at least one bookmark to create a Tesla handoff.</Text>
                )}
              </View>

              <View style={styles.card}>
                <Text style={styles.cardTitle}>Decoded payload</Text>
                {decodedTrip ? <DecodedTrip trip={decodedTrip} /> : <Text style={styles.emptyText}>Invalid trip link.</Text>}
              </View>
            </View>
          ) : null}
        </ScrollView>
      </View>
    </SafeAreaView>
  );
}

function defaultSelectedIds(places: Place[]) {
  return places.slice(0, 2).map((place) => place.id);
}

function TabButton({
  label,
  active,
  onPress,
}: {
  label: string;
  active: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable onPress={onPress} style={[styles.tabButton, active && styles.tabButtonActive]}>
      <Text style={[styles.tabLabel, active && styles.tabLabelActive]}>{label}</Text>
    </Pressable>
  );
}

function Chip({
  label,
  active,
  onPress,
}: {
  label: string;
  active: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable onPress={onPress} style={[styles.chip, active && styles.chipActive]}>
      <Text style={[styles.chipText, active && styles.chipTextActive]}>{label}</Text>
    </Pressable>
  );
}

function SummaryPill({ label }: { label: string }) {
  return (
    <View style={styles.summaryPill}>
      <Text style={styles.summaryPillText}>{label}</Text>
    </View>
  );
}

function PlaceCard({
  place,
  selected,
  onToggle,
}: {
  place: Place;
  selected: boolean;
  onToggle: () => void;
}) {
  return (
    <View style={styles.placeCard}>
      <View style={styles.placeHeader}>
        <View style={styles.placeTitleBlock}>
          <Text style={styles.placeTitle}>{place.name}</Text>
          <Text style={styles.placeSubtitle}>{place.address}</Text>
        </View>
        <Pressable onPress={onToggle} style={[styles.selectButton, selected && styles.selectButtonActive]}>
          <Text style={[styles.selectButtonText, selected && styles.selectButtonTextActive]}>
            {selected ? "In Trip" : "Add"}
          </Text>
        </Pressable>
      </View>
      <Text style={styles.placeMeta}>
        {categoryLabel[place.category]} · {statusLabel[place.status]} · {place.sourcePlatform}
      </Text>
      {place.note ? <Text style={styles.placeNote}>{place.note}</Text> : null}
    </View>
  );
}

function LabeledInput({
  label,
  value,
  onChangeText,
  multiline = false,
  placeholder,
}: {
  label: string;
  value: string;
  onChangeText: (text: string) => void;
  multiline?: boolean;
  placeholder?: string;
}) {
  return (
    <View style={styles.inputGroup}>
      <Text style={styles.inputLabel}>{label}</Text>
      <TextInput
        value={value}
        onChangeText={onChangeText}
        multiline={multiline}
        style={[styles.input, multiline && styles.inputMultiline]}
        placeholder={placeholder}
        placeholderTextColor="#8A857C"
      />
    </View>
  );
}

function ActionButton({
  label,
  onPress,
  tone = "primary",
  compact = false,
}: {
  label: string;
  onPress: () => void;
  tone?: "primary" | "secondary";
  compact?: boolean;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={[
        styles.actionButton,
        tone === "secondary" && styles.actionButtonSecondary,
        compact && styles.actionButtonCompact,
      ]}
    >
      <Text style={[styles.actionButtonText, tone === "secondary" && styles.actionButtonTextSecondary]}>
        {label}
      </Text>
    </Pressable>
  );
}

function DecodedTrip({ trip }: { trip: SharedTripData }) {
  return (
    <View>
      <Text style={styles.previewHeadline}>{trip.name}</Text>
      <Text style={styles.previewSubhead}>{trip.city || "No city set"}</Text>
      {trip.stops.map((stop, index) => (
        <View key={stop.id} style={styles.previewStop}>
          <Text style={styles.previewStopTitle}>
            {index + 1}. {stop.name}
          </Text>
          <Text style={styles.previewStopMeta}>{stop.address}</Text>
          <Text style={styles.previewStopMeta}>
            {stop.time || "No time"} · {stop.lat.toFixed(4)}, {stop.lng.toFixed(4)}
          </Text>
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: "#F5EFE5",
  },
  loadingWrap: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
  },
  loadingText: {
    fontSize: 16,
    fontWeight: "700",
    color: "#5E584E",
  },
  appShell: {
    flex: 1,
    paddingHorizontal: 18,
    paddingTop: 18,
  },
  header: {
    marginBottom: 16,
    gap: 6,
  },
  brand: {
    fontSize: 30,
    fontWeight: "800",
    color: "#1B1816",
  },
  subtitle: {
    fontSize: 14,
    lineHeight: 20,
    color: "#5E584E",
  },
  tabRow: {
    flexDirection: "row",
    gap: 8,
    marginBottom: 16,
  },
  tabButton: {
    flex: 1,
    borderRadius: 16,
    backgroundColor: "#E7DED0",
    paddingVertical: 12,
    alignItems: "center",
  },
  tabButtonActive: {
    backgroundColor: "#CB623D",
  },
  tabLabel: {
    fontSize: 14,
    fontWeight: "700",
    color: "#544B43",
  },
  tabLabelActive: {
    color: "#FFF8F0",
  },
  content: {
    paddingBottom: 32,
  },
  section: {
    gap: 14,
  },
  sectionTitle: {
    fontSize: 22,
    fontWeight: "800",
    color: "#1B1816",
  },
  filterRow: {
    gap: 8,
    paddingVertical: 4,
  },
  chip: {
    borderRadius: 999,
    paddingHorizontal: 14,
    paddingVertical: 9,
    backgroundColor: "#EDE4D7",
  },
  chipActive: {
    backgroundColor: "#1B1816",
  },
  chipText: {
    fontSize: 13,
    fontWeight: "700",
    color: "#5E584E",
  },
  chipTextActive: {
    color: "#FFF8F0",
  },
  summaryRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 8,
  },
  inlineActionRow: {
    flexDirection: "row",
    gap: 10,
  },
  summaryPill: {
    borderRadius: 999,
    backgroundColor: "#EEE3D4",
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  summaryPillText: {
    fontSize: 12,
    fontWeight: "700",
    color: "#544B43",
  },
  placeCard: {
    backgroundColor: "#FFF9F1",
    borderRadius: 22,
    padding: 16,
    gap: 8,
    borderWidth: 1,
    borderColor: "#E5D9C8",
  },
  placeHeader: {
    flexDirection: "row",
    gap: 12,
    alignItems: "flex-start",
  },
  placeTitleBlock: {
    flex: 1,
    gap: 4,
  },
  placeTitle: {
    fontSize: 18,
    fontWeight: "800",
    color: "#1B1816",
  },
  placeSubtitle: {
    fontSize: 13,
    lineHeight: 18,
    color: "#6A645B",
  },
  placeMeta: {
    fontSize: 12,
    fontWeight: "700",
    color: "#A05A3A",
    textTransform: "capitalize",
  },
  placeNote: {
    fontSize: 13,
    lineHeight: 18,
    color: "#524A42",
  },
  selectButton: {
    borderRadius: 999,
    paddingHorizontal: 14,
    paddingVertical: 10,
    backgroundColor: "#E7DED0",
  },
  selectButtonActive: {
    backgroundColor: "#CB623D",
  },
  selectButtonText: {
    fontSize: 12,
    fontWeight: "800",
    color: "#544B43",
  },
  selectButtonTextActive: {
    color: "#FFF8F0",
  },
  card: {
    backgroundColor: "#FFF9F1",
    borderRadius: 22,
    padding: 16,
    gap: 12,
    borderWidth: 1,
    borderColor: "#E5D9C8",
  },
  cardTitle: {
    fontSize: 16,
    fontWeight: "800",
    color: "#1B1816",
  },
  helperText: {
    fontSize: 13,
    lineHeight: 18,
    color: "#675E56",
  },
  successText: {
    fontSize: 13,
    fontWeight: "700",
    color: "#8A4B2F",
  },
  inputGroup: {
    gap: 6,
  },
  inputLabel: {
    fontSize: 12,
    fontWeight: "800",
    color: "#675E56",
    textTransform: "uppercase",
  },
  input: {
    borderRadius: 16,
    backgroundColor: "#F7F0E6",
    borderWidth: 1,
    borderColor: "#E2D6C4",
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
    color: "#1B1816",
  },
  inputMultiline: {
    minHeight: 84,
    textAlignVertical: "top",
  },
  stopRow: {
    flexDirection: "row",
    gap: 12,
    alignItems: "flex-start",
  },
  stopIndex: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: "#CB623D",
    alignItems: "center",
    justifyContent: "center",
    marginTop: 2,
  },
  stopIndexText: {
    color: "#FFF8F0",
    fontWeight: "800",
    fontSize: 13,
  },
  stopBody: {
    flex: 1,
    gap: 4,
  },
  stopName: {
    fontSize: 16,
    fontWeight: "800",
    color: "#1B1816",
  },
  stopMeta: {
    fontSize: 13,
    color: "#6A645B",
  },
  actionButton: {
    borderRadius: 16,
    backgroundColor: "#CB623D",
    paddingHorizontal: 16,
    paddingVertical: 14,
    alignItems: "center",
    flex: 1,
  },
  actionButtonSecondary: {
    backgroundColor: "#EEE3D4",
  },
  actionButtonCompact: {
    minHeight: 48,
    justifyContent: "center",
  },
  actionButtonText: {
    color: "#FFF8F0",
    fontWeight: "800",
    fontSize: 15,
  },
  actionButtonTextSecondary: {
    color: "#2D2823",
  },
  codeBlock: {
    fontSize: 12,
    lineHeight: 18,
    color: "#3E3832",
  },
  nextStopCard: {
    gap: 8,
  },
  previewHeadline: {
    fontSize: 18,
    fontWeight: "800",
    color: "#1B1816",
    marginBottom: 4,
  },
  previewSubhead: {
    fontSize: 13,
    color: "#6A645B",
    marginBottom: 12,
  },
  previewStop: {
    paddingVertical: 10,
    borderTopWidth: 1,
    borderTopColor: "#E9DECF",
  },
  previewStopTitle: {
    fontSize: 15,
    fontWeight: "700",
    color: "#1B1816",
    marginBottom: 4,
  },
  previewStopMeta: {
    fontSize: 12,
    lineHeight: 18,
    color: "#6A645B",
  },
  emptyText: {
    fontSize: 14,
    color: "#6A645B",
  },
});
