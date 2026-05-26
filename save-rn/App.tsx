import AsyncStorage from "@react-native-async-storage/async-storage";
import * as Clipboard from "expo-clipboard";
import { StatusBar } from "expo-status-bar";
import { useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
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
import { createPlace, createTrip, fetchPlaces, fetchTrips, hasApiConfig, SaveAuth } from "./src/api";
import { parseSharedLink } from "./src/importLink";
import {
  categoryLabel,
  Place,
  PlaceCategory,
  SharedTripData,
  TripRecord,
  statusLabel,
} from "./src/models";
import { hasPrivyConfig, useOptionalPrivy, SavePrivyProvider } from "./src/privy";
import {
  buildAppleMapsUrl,
  buildSharedTripData,
  buildTripLink,
  decodeTripLink,
  isSaveTripLink,
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

const storageKey = "@save-rn/bookmarks";
const legacyStorageKey = "@wanderly-rn/bookmarks";
const guestIdStorageKey = "@save-rn/guest-id";
const legacyGuestIdStorageKey = "@wanderly-rn/guest-id";
const seededSamplePlaceIds = new Set(["tartine", "ramen-nagi", "the-interval", "palace-of-fine-arts"]);

export default function App() {
  return (
    <SavePrivyProvider>
      <SaveApp />
    </SavePrivyProvider>
  );
}

function SaveApp() {
  const privy = useOptionalPrivy();
  const privyEnabled = hasPrivyConfig();
  const apiEnabled = hasApiConfig();
  const authReady = !privyEnabled || Boolean(privy?.ready);
  const authenticated = Boolean(privy?.authenticated);

  const [activeTab, setActiveTab] = useState<TabKey>("places");
  const [activeCategory, setActiveCategory] = useState<PlaceCategory | "all">("all");
  const [tripName, setTripName] = useState("Weekend Drive");
  const [tripCity, setTripCity] = useState("Miami");
  const [bookmarks, setBookmarks] = useState<Place[]>([]);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [savedTrips, setSavedTrips] = useState<TripRecord[]>([]);
  const [importLink, setImportLink] = useState("");
  const [importMessage, setImportMessage] = useState("");
  const [pendingImport, setPendingImport] = useState<Place | null>(null);
  const [incomingTrip, setIncomingTrip] = useState<SharedTripData | null>(null);
  const [guestId, setGuestId] = useState<string | null>(null);
  const [isReady, setIsReady] = useState(false);
  const [isSyncing, setIsSyncing] = useState(false);

  useEffect(() => {
    void hydrateInitialTripLink();

    const subscription = Linking.addEventListener("url", ({ url }) => {
      applyIncomingTripLink(url);
    });
    return () => subscription.remove();
  }, []);

  useEffect(() => {
    void bootstrap();
  }, [authReady, authenticated]);

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
  const previewTrip = incomingTrip ?? decodedTrip;
  const nextStop = selectedPlaces[0];
  const importedCount = bookmarks.filter((place) => Boolean(place.sourceUrl)).length;

  async function hydrateInitialTripLink() {
    const initialUrl = await Linking.getInitialURL();
    if (initialUrl) {
      applyIncomingTripLink(initialUrl);
      return;
    }

    if (typeof window !== "undefined" && window.location?.href) {
      applyIncomingTripLink(window.location.href);
    }
  }

  function applyIncomingTripLink(url: string) {
    if (!isSaveTripLink(url)) return;

    const trip = decodeTripLink(url);
    if (!trip) return;

    setIncomingTrip(trip);
    setTripName(trip.name);
    setTripCity(trip.city);
    setActiveTab("share");
    setImportMessage(`Opened shared trip: ${trip.name}`);
  }

  async function bootstrap() {
    if (!authReady) return;

    setIsReady(false);
    try {
      if (apiEnabled) {
        await loadRemoteData(await resolveAuthContext());
      } else {
        await loadLocalBookmarks();
        setSavedTrips([]);
      }
    } finally {
      setIsReady(true);
    }
  }

  async function loadLocalBookmarks() {
    try {
      const raw = await readMigratedStorageValue(storageKey, legacyStorageKey);
      const loaded = raw ? removeSeededSamplePlaces((JSON.parse(raw) as Place[]) ?? []) : [];
      setBookmarks(loaded);
      syncSelectedIds(loaded);
    } catch {
      setBookmarks([]);
      syncSelectedIds([]);
    }
  }

  async function loadRemoteData(auth: SaveAuth) {
    setIsSyncing(true);
    try {
      const [remotePlaces, remoteTrips] = await Promise.all([
        fetchPlaces(auth),
        fetchTrips(auth),
      ]);

      setBookmarks(remotePlaces);
      setSavedTrips(remoteTrips);
      syncSelectedIds(remotePlaces);
    } catch (error) {
      setImportMessage(
        error instanceof Error ? `Sync failed: ${error.message}` : "Sync failed."
      );
      setBookmarks([]);
      setSavedTrips([]);
      syncSelectedIds([]);
    } finally {
      setIsSyncing(false);
    }
  }

  function syncSelectedIds(loaded: Place[]) {
    setSelectedIds((current) =>
      current.length > 0
        ? current.filter((id) => loaded.some((place) => place.id === id))
        : defaultSelectedIds(loaded)
    );
  }

  async function persistLocalBookmarks(next: Place[]) {
    setBookmarks(next);
    await AsyncStorage.setItem(storageKey, JSON.stringify(next));
  }

  async function resolveAuthContext(): Promise<SaveAuth> {
    if (authenticated && privy) {
      const accessToken = await privy.getAccessToken();
      if (!accessToken) {
        throw new Error("Privy access token missing. Try signing in again.");
      }
      return { accessToken };
    }

    const resolvedGuestId = await ensureGuestId();
    return { guestId: resolvedGuestId };
  }

  async function ensureGuestId(): Promise<string> {
    if (guestId) return guestId;

    const stored = await readMigratedStorageValue(guestIdStorageKey, legacyGuestIdStorageKey);
    const nextGuestId = stored && stored.startsWith("guest_") ? stored : createGuestId();
    if (nextGuestId !== stored) {
      await AsyncStorage.setItem(guestIdStorageKey, nextGuestId);
    }
    setGuestId(nextGuestId);
    return nextGuestId;
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
      Alert.alert(
        "Unsupported link",
        "Paste a Google Maps, Apple Maps, Luma, Instagram, Threads, Xiaohongshu, or normal place link."
      );
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

    if (parsed.importKind !== "place") {
      setPendingImport(parsed);
      setImportMessage(`Review draft import: ${parsed.eventLabel ?? parsed.name}`);
      return;
    }

    await saveBookmark(parsed, `Saved to bookmarks: ${parsed.name}`);
  }

  async function saveBookmark(place: Place, message?: string) {
    let savedPlace = place;

    if (!apiEnabled) {
      const next = [place, ...bookmarks];
      await persistLocalBookmarks(next);
    } else {
      try {
        savedPlace = await createPlace(await resolveAuthContext(), place);
        setBookmarks((current) => [savedPlace, ...current]);
      } catch (error) {
        Alert.alert("Save failed", error instanceof Error ? error.message : "Could not save bookmark.");
        return;
      }
    }

    setPendingImport(null);
    setSelectedIds((current) => [savedPlace.id, ...current.filter((id) => id !== savedPlace.id)]);
    setImportMessage(message ?? `Saved to bookmarks: ${savedPlace.name}`);
    setImportLink("");
  }

  async function saveRefinedImport() {
    if (!pendingImport) return;
    if (pendingImport.importKind !== "place" && pendingImport.latitude === 0 && pendingImport.longitude === 0) {
      Alert.alert(
        "Needs confirmed location",
        "Add a map link or confirmed coordinates before saving this social draft as a bookmark."
      );
      return;
    }
    await saveBookmark(pendingImport, `Saved refined stop: ${pendingImport.name}`);
  }

  async function saveTripToAccount() {
    if (!apiEnabled) {
      Alert.alert("Backend not configured", "Add EXPO_PUBLIC_SAVE_API_URL first.");
      return;
    }
    if (selectedPlaces.length === 0) {
      Alert.alert("No stops selected", "Add bookmarks to the trip first.");
      return;
    }

    try {
      const trip = await createTrip(await resolveAuthContext(), {
        name: tripName,
        city: tripCity,
        places: selectedPlaces,
      });
      setSavedTrips((current) => [trip, ...current.filter((item) => item.id !== trip.id)]);
      setImportMessage(`Saved trip: ${trip.name}`);
    } catch (error) {
      Alert.alert("Save failed", error instanceof Error ? error.message : "Could not save trip.");
    }
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
      message: `SAV-E trip: ${tripLink}`,
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
      `SAV-E trip: ${tripName}`,
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

  async function handleAuthAction() {
    if (!privyEnabled) {
      Alert.alert("Privy not configured", "Set EXPO_PUBLIC_PRIVY_APP_ID and EXPO_PUBLIC_PRIVY_APP_CLIENT_ID.");
      return;
    }
    if (!privy) return;
    if (authenticated) {
      await privy.logout();
      setImportMessage(apiEnabled ? "Signed out. Continuing as a guest on this device." : "Signed out. Local bookmarks stay in this browser only.");
      return;
    }
    privy.login();
  }

  if (!isReady) {
    return (
      <SafeAreaView style={styles.safeArea}>
        <View style={styles.loadingWrap}>
          <ActivityIndicator size="small" color={palette.ink} />
          <Text style={styles.loadingText}>Loading SAV-E...</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <View style={styles.appShell}>
        <View style={styles.header}>
          <Text style={styles.brand}>SAV-E</Text>
          <Text style={styles.subtitle}>
            Save places, refine event stops, and turn bookmarks into a trip you can share or hand off.
          </Text>
        </View>

        <View style={styles.card}>
          <View style={styles.authRow}>
            <View style={styles.authCopy}>
              <Text style={styles.cardTitle}>Account</Text>
              <Text style={styles.helperText}>
                {authenticated
                  ? "Signed in with Privy. Places and trips sync with Railway."
                  : privyEnabled
                    ? "Guest mode saves on this device. Sign in with Privy to sync across devices."
                    : apiEnabled
                      ? "Guest mode saves to Railway for this browser. Privy sign-in is not configured."
                      : "Privy web auth is not configured yet. Local bookmarks stay in this browser only."}
              </Text>
            </View>
            {privyEnabled ? (
              <Pressable onPress={handleAuthAction} style={styles.authButton}>
                <Text style={styles.authButtonText}>{authenticated ? "Sign out" : "Sign in"}</Text>
              </Pressable>
            ) : null}
          </View>
          {isSyncing ? <Text style={styles.syncText}>Syncing account data...</Text> : null}
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
                  placeholder="Google Maps, Apple Maps, Luma, Instagram, Threads..."
                />
                <View style={styles.inlineActionRow}>
                  <ActionButton label="Import from Clipboard" onPress={importFromClipboard} tone="secondary" compact />
                  <ActionButton label="Save to Bookmarks" onPress={importSharedLink} compact />
                </View>
                <Text style={styles.helperText}>
                  Maps links can save directly. Events and social links become drafts for review before saving.
                </Text>
                {importMessage ? <Text style={styles.successText}>{importMessage}</Text> : null}
              </View>

              {pendingImport ? (
                <View style={styles.card}>
                  <Text style={styles.cardTitle}>Review imported draft</Text>
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
                    placeholder="Add source context, meetup note, or arrival details"
                  />
                  <View style={styles.inlineActionRow}>
                    <ActionButton label="Dismiss" onPress={dismissPendingImport} tone="secondary" compact />
                    <ActionButton label="Save Bookmark" onPress={saveRefinedImport} compact />
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
              {visiblePlaces.length === 0 ? (
                <View style={styles.emptyPanel}>
                  <Text style={styles.emptyTitle}>No bookmarks yet</Text>
                  <Text style={styles.emptyText}>
                    Import a place link to start. Nothing here is prefilled with sample places.
                  </Text>
                </View>
              ) : null}
            </View>
          ) : null}

          {activeTab === "trip" ? (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Trip planner</Text>
              <View style={styles.card}>
                <LabeledInput label="Trip name" value={tripName} onChangeText={setTripName} />
                <LabeledInput label="City" value={tripCity} onChangeText={setTripCity} />
                <Text style={styles.helperText}>
                  {authenticated
                    ? "Signed in mode saves bookmarks and trips to your SAV-E account."
                    : apiEnabled
                      ? "Guest mode saves bookmarks and trips for this browser. Sign in to sync across devices."
                      : "Local mode works in this browser only. Configure the backend to persist."}
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
                <Text style={styles.cardTitle}>Trip actions</Text>
                <ActionButton
                  label={authenticated ? "Save Trip to Account" : "Save Trip as Guest"}
                  onPress={saveTripToAccount}
                />
                <ActionButton label="Share SAV-E Trip Link" onPress={shareTripLink} tone="secondary" />
                <ActionButton label="Open Trip Link" onPress={openTripLink} tone="secondary" />
              </View>

              {savedTrips.length > 0 ? (
                <View style={styles.card}>
                  <Text style={styles.cardTitle}>Saved trips</Text>
                  {savedTrips.map((trip) => (
                    <View key={trip.id} style={styles.savedTripRow}>
                      <Text style={styles.stopName}>{trip.name}</Text>
                      <Text style={styles.stopMeta}>
                        {trip.city || "No city"} · {trip.tripStops.length} stops
                      </Text>
                    </View>
                  ))}
                </View>
              ) : null}
            </View>
          ) : null}

          {activeTab === "share" ? (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Tesla handoff</Text>

              {incomingTrip ? (
                <View style={styles.card}>
                  <Text style={styles.cardTitle}>Opened trip link</Text>
                  <DecodedTrip trip={incomingTrip} />
                </View>
              ) : null}

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
                {previewTrip ? <DecodedTrip trip={previewTrip} /> : <Text style={styles.emptyText}>Invalid trip link.</Text>}
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

async function readMigratedStorageValue(primaryKey: string, legacyKey: string): Promise<string | null> {
  const primaryValue = await AsyncStorage.getItem(primaryKey);
  if (primaryValue) return primaryValue;

  const legacyValue = await AsyncStorage.getItem(legacyKey);
  if (legacyValue) {
    await AsyncStorage.setItem(primaryKey, legacyValue);
  }
  return legacyValue;
}

function removeSeededSamplePlaces(places: Place[]) {
  return places.filter((place) => !seededSamplePlaceIds.has(place.id));
}

function createGuestId() {
  const fallback = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (character) => {
    const random = Math.floor(Math.random() * 16);
    const value = character === "x" ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
  const uuid = globalThis.crypto?.randomUUID?.() ?? fallback;
  return `guest_${uuid}`;
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
        placeholderTextColor={palette.muted}
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

const palette = {
  cream: "#FFF7E8",
  paper: "#FFF0D6",
  yellow: "#FFE24A",
  coral: "#FF8A65",
  sky: "#7EDAEF",
  mint: "#B8F5C8",
  pink: "#FFD7E8",
  ink: "#111111",
  muted: "#6A645B",
  border: "#111111",
};

const hardShadow = {};

const smallShadow = {};

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: palette.cream },
  loadingWrap: { flex: 1, alignItems: "center", justifyContent: "center", gap: 10 },
  loadingText: { fontSize: 16, fontWeight: "800", color: palette.ink },
  appShell: { flex: 1, paddingHorizontal: 18, paddingTop: 18 },
  header: { marginBottom: 16, gap: 6 },
  brand: { fontSize: 32, fontWeight: "900", color: palette.ink },
  subtitle: { fontSize: 14, lineHeight: 20, color: palette.muted, fontWeight: "600" },
  tabRow: { flexDirection: "row", gap: 8, marginBottom: 16 },
  tabButton: {
    flex: 1,
    borderRadius: 16,
    backgroundColor: palette.paper,
    borderWidth: 2,
    borderColor: palette.border,
    paddingVertical: 12,
    alignItems: "center",
    ...smallShadow,
  },
  tabButtonActive: { backgroundColor: palette.yellow },
  tabLabel: { fontSize: 14, fontWeight: "900", color: palette.ink },
  tabLabelActive: { color: palette.ink },
  content: { paddingBottom: 32 },
  section: { gap: 14 },
  sectionTitle: { fontSize: 23, fontWeight: "900", color: palette.ink },
  filterRow: { gap: 8, paddingVertical: 4 },
  chip: {
    borderRadius: 999,
    paddingHorizontal: 14,
    paddingVertical: 9,
    backgroundColor: palette.paper,
    borderWidth: 2,
    borderColor: palette.border,
  },
  chipActive: { backgroundColor: palette.yellow },
  chipText: { fontSize: 13, fontWeight: "900", color: palette.ink },
  chipTextActive: { color: palette.ink },
  card: {
    backgroundColor: palette.paper,
    borderRadius: 22,
    padding: 16,
    gap: 12,
    borderWidth: 2,
    borderColor: palette.border,
    ...hardShadow,
  },
  cardTitle: { fontSize: 16, fontWeight: "900", color: palette.ink },
  authRow: { flexDirection: "row", gap: 12, alignItems: "center" },
  authCopy: { flex: 1, gap: 4 },
  authButton: {
    borderRadius: 14,
    backgroundColor: palette.yellow,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderWidth: 2,
    borderColor: palette.border,
    ...smallShadow,
  },
  authButtonText: { color: palette.ink, fontWeight: "900", fontSize: 13 },
  syncText: { fontSize: 12, color: palette.coral, fontWeight: "900" },
  helperText: { fontSize: 13, lineHeight: 18, color: palette.muted, fontWeight: "600" },
  successText: { fontSize: 13, fontWeight: "900", color: palette.coral },
  inlineActionRow: { flexDirection: "row", gap: 10 },
  summaryRow: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  summaryPill: {
    borderRadius: 999,
    backgroundColor: palette.pink,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderWidth: 2,
    borderColor: palette.border,
  },
  summaryPillText: { fontSize: 12, fontWeight: "900", color: palette.ink },
  placeCard: {
    backgroundColor: palette.paper,
    borderRadius: 22,
    padding: 16,
    gap: 8,
    borderWidth: 2,
    borderColor: palette.border,
    ...hardShadow,
  },
  placeHeader: { flexDirection: "row", gap: 12, alignItems: "flex-start" },
  placeTitleBlock: { flex: 1, gap: 4 },
  placeTitle: { fontSize: 18, fontWeight: "900", color: palette.ink },
  placeSubtitle: { fontSize: 13, lineHeight: 18, color: palette.muted },
  placeMeta: { fontSize: 12, fontWeight: "900", color: palette.coral, textTransform: "capitalize" },
  placeNote: { fontSize: 13, lineHeight: 18, color: palette.ink },
  selectButton: {
    borderRadius: 999,
    paddingHorizontal: 14,
    paddingVertical: 10,
    backgroundColor: palette.paper,
    borderWidth: 2,
    borderColor: palette.border,
  },
  selectButtonActive: { backgroundColor: palette.mint },
  selectButtonText: { fontSize: 12, fontWeight: "900", color: palette.ink },
  selectButtonTextActive: { color: palette.ink },
  inputGroup: { gap: 6 },
  inputLabel: { fontSize: 12, fontWeight: "900", color: palette.ink, textTransform: "uppercase" },
  input: {
    borderRadius: 16,
    backgroundColor: palette.cream,
    borderWidth: 2,
    borderColor: palette.border,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
    color: palette.ink,
  },
  inputMultiline: { minHeight: 84, textAlignVertical: "top" },
  stopRow: { flexDirection: "row", gap: 12, alignItems: "flex-start" },
  stopIndex: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: palette.yellow,
    alignItems: "center",
    justifyContent: "center",
    marginTop: 2,
    borderWidth: 2,
    borderColor: palette.border,
  },
  stopIndexText: { color: palette.ink, fontWeight: "900", fontSize: 13 },
  stopBody: { flex: 1, gap: 4 },
  stopName: { fontSize: 16, fontWeight: "900", color: palette.ink },
  stopMeta: { fontSize: 13, color: palette.muted },
  actionButton: {
    borderRadius: 16,
    backgroundColor: palette.yellow,
    paddingHorizontal: 16,
    paddingVertical: 14,
    alignItems: "center",
    flex: 1,
    borderWidth: 2,
    borderColor: palette.border,
    ...smallShadow,
  },
  actionButtonSecondary: { backgroundColor: palette.sky },
  actionButtonCompact: { minHeight: 48, justifyContent: "center" },
  actionButtonText: { color: palette.ink, fontWeight: "900", fontSize: 15 },
  actionButtonTextSecondary: { color: palette.ink },
  codeBlock: { fontSize: 12, lineHeight: 18, color: palette.ink },
  savedTripRow: { paddingTop: 10, borderTopWidth: 2, borderTopColor: palette.border, gap: 4 },
  emptyPanel: {
    backgroundColor: palette.paper,
    borderRadius: 22,
    borderWidth: 2,
    borderColor: palette.border,
    padding: 16,
    gap: 6,
    ...hardShadow,
  },
  emptyTitle: { fontSize: 16, fontWeight: "900", color: palette.ink },
  nextStopCard: { gap: 8 },
  previewHeadline: { fontSize: 18, fontWeight: "900", color: palette.ink, marginBottom: 4 },
  previewSubhead: { fontSize: 13, color: palette.muted, marginBottom: 12 },
  previewStop: { paddingVertical: 10, borderTopWidth: 2, borderTopColor: palette.border },
  previewStopTitle: { fontSize: 15, fontWeight: "800", color: palette.ink, marginBottom: 4 },
  previewStopMeta: { fontSize: 12, lineHeight: 18, color: palette.muted },
  emptyText: { fontSize: 14, color: palette.muted },
});
