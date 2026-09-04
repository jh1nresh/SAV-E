import Foundation

/// Clock helpers for itinerary display strings such as `9:00 AM`.
enum TripClock {
    static func minutes(fromDisplay display: String) -> Int? {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let parts = trimmed.split(separator: " ")
        guard let clock = parts.first else { return nil }
        let hm = clock.split(separator: ":")
        guard let hourPart = hm.first, let hour = Int(hourPart) else { return nil }
        let minute = hm.count > 1 ? Int(hm[1]) ?? 0 : 0
        let meridiem = parts.count > 1 ? String(parts[1]) : (hour >= 8 && hour <= 11 ? "AM" : "PM")
        var hour24 = hour % 12
        if meridiem == "PM" { hour24 += 12 }
        if meridiem == "AM" && hour == 12 { hour24 = 0 }
        return hour24 * 60 + minute
    }

    static func display(from minutes: Int) -> String {
        let wrapped = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60)
        let hour24 = wrapped / 60
        let minute = wrapped % 60
        let meridiem = hour24 >= 12 ? "PM" : "AM"
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return "\(hour12):\(String(format: "%02d", minute)) \(meridiem)"
    }
}

/// Arrival, departure, and lodging constraints that shrink a day's usable window.
///
/// Savvy does not book flights or hotels. These clocks only decide when a
/// Map Stamp may be scheduled.
struct TripPlanWindows: Equatable, Hashable {
    var arrivalMinutes: Int?
    var departureMinutes: Int?
    var airportBufferMinutes: Int
    var airportTransferMinutes: Int
    var hotelCheckInMinutes: Int
    var hotelCheckOutMinutes: Int
    var dayStartMinutes: Int
    var dayEndMinutes: Int

    static let standard = TripPlanWindows(
        arrivalMinutes: nil,
        departureMinutes: nil,
        airportBufferMinutes: 90,
        airportTransferMinutes: 180,
        hotelCheckInMinutes: 15 * 60,
        hotelCheckOutMinutes: 11 * 60,
        dayStartMinutes: 9 * 60,
        dayEndMinutes: 21 * 60
    )
}

struct SaveDayRhythmResult: Equatable {
    var stops: [ItineraryStop]
    var windowNote: String?
    var gaps: [TripGap]
}

/// Assigns meal, lodging, and activity times inside a travel window.
///
/// Geographic order is the caller's job. This only decides *when*, and it will
/// insert labeled unsaved suggestions into empty meal or afternoon slots
/// without promoting them to Map Stamps.
struct SaveDayRhythmScheduler {
    private enum SlotKind: Equatable {
        case breakfast
        case lunch
        case dinner
        case activity
        case checkIn
        case checkOut

        var duration: Int {
            switch self {
            case .breakfast: return 60
            case .lunch: return 90
            case .dinner: return 105
            case .activity: return 90
            case .checkIn: return 45
            case .checkOut: return 30
            }
        }
    }

    private struct Slot {
        var start: Int
        var kind: SlotKind
        var duration: Int { kind.duration }
        var end: Int { start + duration }
    }

    func schedule(
        orderedPlaces: [Place],
        unsavedCandidates: [SaveMapCandidate],
        lodging: Place?,
        dayNumber: Int,
        dayCount: Int,
        windows: TripPlanWindows,
        outputLanguage: AppLanguage
    ) -> SaveDayRhythmResult {
        let isFirst = dayNumber == 1
        let isLast = dayNumber == dayCount
        let bounds = usableWindow(
            isFirst: isFirst,
            isLast: isLast,
            windows: windows
        )
        var remainingPlaces = orderedPlaces.filter { $0.category != .stay }
        var remainingUnsaved = unsavedCandidates
        let lodgingPlace = lodging
        var lodgingCandidate: SaveMapCandidate?
        if lodgingPlace == nil,
           let index = remainingUnsaved.firstIndex(where: { $0.category == .stay }) {
            lodgingCandidate = remainingUnsaved.remove(at: index)
        }
        let hasLodging = lodgingPlace != nil || lodgingCandidate != nil
        let lodgingName = lodgingPlace?.name ?? lodgingCandidate?.title
        let windowNote = note(
            bounds: bounds,
            isFirst: isFirst,
            isLast: isLast,
            windows: windows,
            lodgingName: lodgingName,
            outputLanguage: outputLanguage
        )
        var stops: [ItineraryStop] = []
        var gaps: [TripGap] = []
        let dayId = "day-\(dayNumber)"
        let slots = template(
            start: bounds.start,
            end: bounds.end,
            includeCheckIn: isFirst && hasLodging,
            includeCheckOut: isLast && hasLodging && dayCount >= 2,
            checkInMinutes: max(bounds.start, windows.hotelCheckInMinutes),
            checkOutMinutes: windows.hotelCheckOutMinutes
        )

        for slot in slots {
            switch slot.kind {
            case .checkIn:
                if let lodgingPlace {
                    stops.append(lodgingStop(
                        lodgingPlace,
                        start: slot.start,
                        duration: slot.duration,
                        checkIn: true,
                        outputLanguage: outputLanguage
                    ))
                } else if let lodgingCandidate {
                    stops.append(unsavedLodgingStop(
                        lodgingCandidate,
                        start: slot.start,
                        duration: slot.duration,
                        checkIn: true,
                        outputLanguage: outputLanguage
                    ))
                }
            case .checkOut:
                if let lodgingPlace {
                    stops.append(lodgingStop(
                        lodgingPlace,
                        start: slot.start,
                        duration: slot.duration,
                        checkIn: false,
                        outputLanguage: outputLanguage
                    ))
                } else if let lodgingCandidate {
                    stops.append(unsavedLodgingStop(
                        lodgingCandidate,
                        start: slot.start,
                        duration: slot.duration,
                        checkIn: false,
                        outputLanguage: outputLanguage
                    ))
                }
            case .breakfast, .lunch, .dinner:
                let mealCategories: Set<PlaceCategory> = slot.kind == .breakfast
                    ? [.cafe]
                    : (slot.kind == .dinner ? [.food, .bar] : [.food])
                if let index = remainingPlaces.firstIndex(where: { mealCategories.contains($0.category) }) {
                    let place = remainingPlaces.remove(at: index)
                    stops.append(stampStop(place, start: slot.start, duration: slot.duration, outputLanguage: outputLanguage))
                } else if let index = remainingUnsaved.firstIndex(where: {
                    mealCategories.contains($0.category ?? .food)
                }) {
                    let candidate = remainingUnsaved.remove(at: index)
                    stops.append(unsavedStop(candidate, start: slot.start, duration: slot.duration, outputLanguage: outputLanguage))
                } else {
                    gaps.append(mealGap(for: slot.kind, dayId: dayId, outputLanguage: outputLanguage))
                }
            case .activity:
                if let index = remainingPlaces.firstIndex(where: {
                    [.attraction, .shopping, .cafe].contains($0.category)
                }) {
                    let place = remainingPlaces.remove(at: index)
                    stops.append(stampStop(place, start: slot.start, duration: slot.duration, outputLanguage: outputLanguage))
                } else if let index = remainingPlaces.firstIndex(where: { $0.category != .food && $0.category != .bar }) {
                    let place = remainingPlaces.remove(at: index)
                    stops.append(stampStop(place, start: slot.start, duration: slot.duration, outputLanguage: outputLanguage))
                } else if let index = remainingUnsaved.firstIndex(where: {
                    [.attraction, .shopping, .cafe].contains($0.category ?? .attraction)
                }) {
                    let candidate = remainingUnsaved.remove(at: index)
                    stops.append(unsavedStop(candidate, start: slot.start, duration: slot.duration, outputLanguage: outputLanguage))
                } else if let index = remainingUnsaved.firstIndex(where: {
                    $0.category != .stay
                }) {
                    let candidate = remainingUnsaved.remove(at: index)
                    stops.append(unsavedStop(candidate, start: slot.start, duration: slot.duration, outputLanguage: outputLanguage))
                } else {
                    gaps.append(TripGap(
                        id: "\(dayId)-missing-afternoon-activity",
                        type: .missingAfternoonActivity,
                        dayId: dayId,
                        severity: .medium,
                        message: outputLanguage.localized(
                            english: "There is no clear afternoon activity between meals.",
                            traditionalChinese: "兩餐之間還沒有明確的下午活動。"
                        )
                    ))
                }
            }
        }

        // Leftover Map Stamps still belong on this day; append inside the window
        // rather than dropping user memory.
        var cursor = bounds.start
        if let last = stops.max(by: {
            (TripClock.minutes(fromDisplay: $0.time ?? "") ?? 0)
                < (TripClock.minutes(fromDisplay: $1.time ?? "") ?? 0)
        }), let start = TripClock.minutes(fromDisplay: last.time ?? "") {
            cursor = start + (last.duration ?? 60) + 20
        }
        for place in remainingPlaces where cursor + 60 <= bounds.end {
            stops.append(stampStop(place, start: cursor, duration: 75, outputLanguage: outputLanguage))
            cursor += 95
        }

        stops = compact(stops, bounds: bounds)

        if dayCount >= 2, !hasLodging, isFirst {
            gaps.append(TripGap(
                id: "\(dayId)-missing-lodging",
                type: .missingLodging,
                dayId: dayId,
                severity: .high,
                message: outputLanguage.localized(
                    english: "This trip has no saved stay. Add a hotel Map Stamp or approve an unsaved lodging suggestion. Savvy does not book rooms.",
                    traditionalChinese: "這趟行程還沒有已存住宿。請加入飯店地圖章，或核准未存的住宿候選。Savvy 不會代訂房間。"
                )
            ))
        }

        return SaveDayRhythmResult(stops: stops, windowNote: windowNote, gaps: gaps)
    }

    func usableWindow(
        isFirst: Bool,
        isLast: Bool,
        windows: TripPlanWindows
    ) -> (start: Int, end: Int) {
        var start = windows.dayStartMinutes
        var end = windows.dayEndMinutes
        if isFirst, let arrival = windows.arrivalMinutes {
            start = max(start, arrival + windows.airportBufferMinutes)
        }
        if isLast, let departure = windows.departureMinutes {
            end = min(end, departure - windows.airportTransferMinutes)
        }
        if end - start < 60 {
            end = start + 60
        }
        return (start, end)
    }

    private func template(
        start: Int,
        end: Int,
        includeCheckIn: Bool,
        includeCheckOut: Bool,
        checkInMinutes: Int,
        checkOutMinutes: Int
    ) -> [Slot] {
        var slots: [Slot] = []
        if includeCheckOut, checkOutMinutes >= start, checkOutMinutes + SlotKind.checkOut.duration <= end {
            slots.append(Slot(start: checkOutMinutes, kind: .checkOut))
        }
        if start <= 10 * 60, start + SlotKind.breakfast.duration <= end {
            slots.append(Slot(start: max(start, 8 * 60 + 30), kind: .breakfast))
        }
        let lunchStart = 12 * 60 + 30
        if start < lunchStart + 30, lunchStart + SlotKind.lunch.duration <= end {
            slots.append(Slot(start: max(start, lunchStart), kind: .lunch))
        }
        if includeCheckIn,
           checkInMinutes >= start,
           checkInMinutes + SlotKind.checkIn.duration <= end {
            slots.append(Slot(start: checkInMinutes, kind: .checkIn))
        }
        var activityStart: Int
        if let lunch = slots.first(where: { $0.kind == .lunch }) {
            activityStart = lunch.end + 20
        } else if let breakfast = slots.first(where: { $0.kind == .breakfast }) {
            activityStart = breakfast.end + 20
        } else if includeCheckOut {
            activityStart = max(start, checkOutMinutes + SlotKind.checkOut.duration + 20)
        } else {
            activityStart = start
        }
        let dinnerStart = 18 * 60 + 30
        if let checkIn = slots.first(where: { $0.kind == .checkIn }) {
            let overlapsCheckIn = activityStart < checkIn.end
                && activityStart + SlotKind.activity.duration > checkIn.start
            if overlapsCheckIn {
                activityStart = checkIn.end + 20
            }
        }
        let activityFitsBeforeDinner = activityStart + SlotKind.activity.duration <= dinnerStart - 15
        let activityFitsInDay = activityStart + SlotKind.activity.duration <= end - 30
        if activityFitsInDay, activityFitsBeforeDinner || dinnerStart + SlotKind.dinner.duration > end {
            slots.append(Slot(start: activityStart, kind: .activity))
        }
        if dinnerStart + SlotKind.dinner.duration <= end, start < dinnerStart {
            slots.append(Slot(start: dinnerStart, kind: .dinner))
        }
        return slots.sorted { $0.start < $1.start }
    }

    private func compact(
        _ stops: [ItineraryStop],
        bounds: (start: Int, end: Int)
    ) -> [ItineraryStop] {
        let sorted = stops.sorted {
            (TripClock.minutes(fromDisplay: $0.time ?? "") ?? 0)
                < (TripClock.minutes(fromDisplay: $1.time ?? "") ?? 0)
        }
        var result: [ItineraryStop] = []
        var cursor = bounds.start
        for stop in sorted {
            let duration = stop.duration ?? 60
            let original = TripClock.minutes(fromDisplay: stop.time ?? "") ?? cursor
            let start = max(original, cursor)
            guard start + duration <= bounds.end else { continue }
            if start == original {
                result.append(stop)
            } else {
                result.append(retimed(stop, start: start))
            }
            cursor = start + duration + 15
        }
        return result
    }

    private func retimed(_ stop: ItineraryStop, start: Int) -> ItineraryStop {
        ItineraryStop(
            id: stop.id,
            placeId: stop.placeId,
            placeState: stop.placeState,
            placeName: stop.placeName,
            time: TripClock.display(from: start),
            duration: stop.duration,
            note: stop.note,
            sourceSummary: stop.sourceSummary,
            risks: stop.risks
        )
    }

    private func stampStop(
        _ place: Place,
        start: Int,
        duration: Int,
        outputLanguage: AppLanguage
    ) -> ItineraryStop {
        ItineraryStop(
            id: UUID(),
            placeId: place.id.uuidString,
            placeState: .confirmedMapStamp,
            placeName: place.name,
            time: TripClock.display(from: start),
            duration: duration,
            note: outputLanguage.localized(
                english: "Confirmed Map Stamp from your Savvy memory.",
                traditionalChinese: "來自你的 Savvy 記憶，已確認為地圖章。"
            ),
            sourceSummary: outputLanguage.localized(
                english: "Map Stamp",
                traditionalChinese: "地圖章"
            ),
            risks: [.hoursUnknown]
        )
    }

    private func unsavedStop(
        _ candidate: SaveMapCandidate,
        start: Int,
        duration: Int,
        outputLanguage: AppLanguage
    ) -> ItineraryStop {
        ItineraryStop(
            id: UUID(),
            placeId: nil,
            placeState: .externalSuggestion,
            placeName: candidate.title,
            time: TripClock.display(from: start),
            duration: duration,
            note: outputLanguage.localized(
                english: "Unsaved Candidate. Approve to keep it on this plan; it will not become a Map Stamp automatically.",
                traditionalChinese: "尚未儲存的候選。核准後才留在行程裡，不會自動變成地圖章。"
            ),
            sourceSummary: outputLanguage.localized(
                english: "Unsaved Candidate",
                traditionalChinese: "尚未儲存"
            ),
            risks: [.externalSuggestion, .hoursUnknown, .bookingUnknown]
        )
    }

    private func unsavedLodgingStop(
        _ candidate: SaveMapCandidate,
        start: Int,
        duration: Int,
        checkIn: Bool,
        outputLanguage: AppLanguage
    ) -> ItineraryStop {
        ItineraryStop(
            id: UUID(),
            placeId: nil,
            placeState: .externalSuggestion,
            placeName: candidate.title,
            time: TripClock.display(from: start),
            duration: duration,
            note: checkIn
                ? outputLanguage.localized(
                    english: "Unsaved lodging suggestion for check-in. Approve to keep it; Savvy does not book the room.",
                    traditionalChinese: "尚未儲存的入住候選。核准後才留下；Savvy 不會代訂房間。"
                )
                : outputLanguage.localized(
                    english: "Unsaved lodging suggestion for check-out. Approve to keep it; Savvy does not book the room.",
                    traditionalChinese: "尚未儲存的退房候選。核准後才留下；Savvy 不會代訂房間。"
                ),
            sourceSummary: outputLanguage.localized(
                english: "Unsaved Candidate",
                traditionalChinese: "尚未儲存"
            ),
            risks: [.externalSuggestion, .bookingUnknown]
        )
    }

    private func lodgingStop(
        _ place: Place,
        start: Int,
        duration: Int,
        checkIn: Bool,
        outputLanguage: AppLanguage
    ) -> ItineraryStop {
        ItineraryStop(
            id: UUID(),
            placeId: place.id.uuidString,
            placeState: .confirmedMapStamp,
            placeName: place.name,
            time: TripClock.display(from: start),
            duration: duration,
            note: checkIn
                ? outputLanguage.localized(
                    english: "Hotel check-in window. Savvy does not book the room.",
                    traditionalChinese: "飯店入住時段。Savvy 不會代訂房間。"
                )
                : outputLanguage.localized(
                    english: "Hotel check-out before the rest of the day. Savvy does not book the room.",
                    traditionalChinese: "先退房再開始當天行程。Savvy 不會代訂房間。"
                ),
            sourceSummary: outputLanguage.localized(
                english: "Stay Map Stamp",
                traditionalChinese: "住宿地圖章"
            ),
            risks: [.bookingUnknown]
        )
    }

    private func mealGap(for kind: SlotKind, dayId: String, outputLanguage: AppLanguage) -> TripGap {
        switch kind {
        case .breakfast:
            return TripGap(
                id: "\(dayId)-missing-breakfast",
                type: .missingBreakfast,
                dayId: dayId,
                severity: .low,
                message: outputLanguage.localized(
                    english: "Breakfast is not clearly covered.",
                    traditionalChinese: "早餐還沒有明確安排。"
                )
            )
        case .lunch:
            return TripGap(
                id: "\(dayId)-missing-lunch",
                type: .missingLunch,
                dayId: dayId,
                severity: .medium,
                message: outputLanguage.localized(
                    english: "Lunch is not clearly covered.",
                    traditionalChinese: "午餐還沒有明確安排。"
                )
            )
        case .dinner:
            return TripGap(
                id: "\(dayId)-missing-dinner",
                type: .missingDinner,
                dayId: dayId,
                severity: .medium,
                message: outputLanguage.localized(
                    english: "Dinner is not clearly covered.",
                    traditionalChinese: "晚餐還沒有明確安排。"
                )
            )
        default:
            return TripGap(
                id: "\(dayId)-missing-afternoon-activity",
                type: .missingAfternoonActivity,
                dayId: dayId,
                severity: .medium,
                message: outputLanguage.localized(
                    english: "There is no clear afternoon activity between meals.",
                    traditionalChinese: "兩餐之間還沒有明確的下午活動。"
                )
            )
        }
    }

    private func note(
        bounds: (start: Int, end: Int),
        isFirst: Bool,
        isLast: Bool,
        windows: TripPlanWindows,
        lodgingName: String?,
        outputLanguage: AppLanguage
    ) -> String? {
        var parts: [String] = []
        if isFirst, let arrival = windows.arrivalMinutes {
            parts.append(outputLanguage.localized(
                english: "Arrive \(TripClock.display(from: arrival)) · first stop after \(TripClock.display(from: bounds.start))",
                traditionalChinese: "抵達 \(TripClock.display(from: arrival)) · \(TripClock.display(from: bounds.start)) 後才排第一站"
            ))
        }
        if isLast, let departure = windows.departureMinutes {
            parts.append(outputLanguage.localized(
                english: "Last stop by \(TripClock.display(from: bounds.end)) · depart \(TripClock.display(from: departure))",
                traditionalChinese: "最晚 \(TripClock.display(from: bounds.end)) 結束 · \(TripClock.display(from: departure)) 出發"
            ))
        }
        if let lodgingName, isFirst {
            parts.append(outputLanguage.localized(
                english: "Check in \(lodgingName) around \(TripClock.display(from: max(bounds.start, windows.hotelCheckInMinutes)))",
                traditionalChinese: "約 \(TripClock.display(from: max(bounds.start, windows.hotelCheckInMinutes))) 入住 \(lodgingName)"
            ))
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }
}
