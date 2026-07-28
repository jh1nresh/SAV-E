import SwiftUI

struct HomeAtlasScreen: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            BrandHeader {
                Button(action: {}) {
                    HStack(spacing: 7) {
                        Image(systemName: "link")
                            .font(.system(size: 15, weight: .medium))
                        Text("Paste a link")
                            .font(AtlasType.display(13))
                    }
                    .foregroundStyle(AtlasPalette.ink)
                    .frame(width: 120, height: 35)
                    .background(AtlasPalette.paper, in: Capsule())
                    .overlay {
                        Capsule().stroke(AtlasPalette.line.opacity(0.34), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("prototype.action.pasteLink")
            }
            .placed(x: 0, y: 48, width: 402, height: 51)
            .accessibilityIdentifier("prototype.home.header")

            Image("HomeAtlasScene")
                .resizable()
                .scaledToFill()
                .clipped()
                .placed(x: 0, y: 99, width: 402, height: 274)
                .accessibilityLabel("Illustrated Tokyo atlas")
                .accessibilityIdentifier("prototype.home.atlas")

            HomeReviewCard()
                .placed(x: 5, y: 354, width: 392, height: 182)
                .accessibilityIdentifier("prototype.home.reviewCard")

            HomeNextTrip()
                .placed(x: 10, y: 542, width: 382, height: 105)
                .accessibilityIdentifier("prototype.home.nextTrip")

            HomeRecentStamps()
                .placed(x: 10, y: 650, width: 382, height: 133)
                .accessibilityIdentifier("prototype.home.recentStamps")
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prototype.home")
    }
}

private struct HomeReviewCard: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(AtlasPalette.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(AtlasPalette.line.opacity(0.30), lineWidth: 1)
                }
                .shadow(color: AtlasPalette.ink.opacity(0.04), radius: 4, y: 1)

            Text("3 clues need your help")
                .font(AtlasType.strong(24))
                .foregroundStyle(AtlasPalette.forest)
                .position(x: 196, y: 32)

            Text("Review and decide what’s worth saving.")
                .font(AtlasType.body(13))
                .foregroundStyle(AtlasPalette.muted)
                .position(x: 196, y: 58)

            Button(action: {}) {
                HStack {
                    Spacer()
                    Text("Review clues")
                        .font(AtlasType.strong(16))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .regular))
                        .padding(.trailing, 14)
                }
                .foregroundStyle(.white)
                .frame(width: 296, height: 41)
                .background(
                    LinearGradient(
                        colors: [AtlasPalette.coral, AtlasPalette.coral.opacity(0.90)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .position(x: 196, y: 93)
            .accessibilityIdentifier("prototype.action.reviewClues")

            Rectangle()
                .fill(AtlasPalette.line.opacity(0.30))
                .frame(width: 1, height: 39)
                .position(x: 196, y: 151)

            HomeMetric(
                value: "3",
                label: "to review",
                systemName: "timer",
                tint: AtlasPalette.lavender
            )
            .frame(width: 150, height: 42)
            .position(x: 121, y: 150)

            HomeMetric(
                value: "18",
                label: "Map Stamps",
                systemName: "arrow.up.right",
                tint: AtlasPalette.mint
            )
            .frame(width: 150, height: 42)
            .position(x: 274, y: 150)
        }
    }
}

private struct HomeMetric: View {
    let value: String
    let label: String
    let systemName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AtlasPalette.ink)
                .frame(width: 38, height: 38)
                .background(tint, in: Circle())

            VStack(alignment: .leading, spacing: -1) {
                Text(value)
                    .font(AtlasType.strong(22))
                    .foregroundStyle(AtlasPalette.forest)
                Text(label)
                    .font(AtlasType.body(12))
                    .foregroundStyle(AtlasPalette.muted)
            }
        }
    }
}

private struct HomeNextTrip: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("NEXT UP")
                .font(AtlasType.strong(11))
                .tracking(1.2)
                .foregroundStyle(AtlasPalette.muted)
                .position(x: 30, y: 12)

            Text("Tokyo Weekend")
                .font(AtlasType.strong(21))
                .foregroundStyle(AtlasPalette.forest)
                .position(x: 75, y: 37)

            Text("Day 2 of 3")
                .font(AtlasType.display(12))
                .foregroundStyle(AtlasPalette.ink)
                .frame(width: 83, height: 28)
                .background(AtlasPalette.lavender, in: Capsule())
                .position(x: 340, y: 36)

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AtlasPalette.forest)
                .position(x: 17, y: 70)

            Text("4 stops planned")
                .font(AtlasType.body(12))
                .foregroundStyle(AtlasPalette.muted)
                .position(x: 92, y: 68)

            Text("Next stop: Tsukiji Outer Market · 9:00 AM")
                .font(AtlasType.regular(12))
                .foregroundStyle(AtlasPalette.muted)
                .position(x: 179, y: 91)

            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AtlasPalette.muted)
                .position(x: 368, y: 77)

            Rectangle()
                .fill(AtlasPalette.line.opacity(0.30))
                .frame(width: 382, height: 1)
                .position(x: 191, y: 104)
        }
    }
}

private struct HomeRecentStamps: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("RECENT MAP STAMPS")
                .font(AtlasType.strong(11))
                .tracking(1.1)
                .foregroundStyle(AtlasPalette.muted)
                .position(x: 78, y: 14)

            Text("See all")
                .font(AtlasType.display(12))
                .foregroundStyle(AtlasPalette.ink)
                .position(x: 354, y: 14)

            HomeStampRow(name: "Shibuya Backstreets", area: "Shibuya", day: "Today")
                .placed(x: 0, y: 27, width: 382, height: 51)

            HomeStampRow(name: "Koffee Mameya", area: "Shibuya", day: "Yesterday")
                .placed(x: 0, y: 78, width: 382, height: 51)
        }
    }
}

private struct HomeStampRow: View {
    let name: String
    let area: String
    let day: String

    var body: some View {
        HStack(spacing: 10) {
            RoundStamp(text: "", style: .mapStamp)

            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(AtlasType.strong(15))
                    .foregroundStyle(AtlasPalette.ink)
                Text("\(area) · Confirmed")
                    .font(AtlasType.regular(11))
                    .foregroundStyle(AtlasPalette.muted)
            }

            Spacer()

            Text(day)
                .font(AtlasType.regular(11))
                .foregroundStyle(AtlasPalette.muted)

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AtlasPalette.muted)
        }
        .padding(.horizontal, 3)
    }
}

struct SavesPocketScreen: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            BrandHeader {
                Button(action: {}) {
                    Image(systemName: "link")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(AtlasPalette.ink)
                        .frame(width: 40, height: 40)
                        .background(AtlasPalette.honey.opacity(0.78), in: RoundedRectangle(cornerRadius: 13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(AtlasPalette.line.opacity(0.28), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("prototype.action.pasteLink")
            }
            .placed(x: 0, y: 48, width: 402, height: 50)
            .accessibilityIdentifier("prototype.saves.header")

            SavesTitleBlock()
                .placed(x: 10, y: 103, width: 382, height: 101)
                .accessibilityIdentifier("prototype.saves.title")

            Image("SavesMemoSorting")
                .resizable()
                .scaledToFit()
                .placed(x: 286, y: 100, width: 112, height: 112)
                .accessibilityLabel("Memo sorting saved cards")

            HStack(spacing: 10) {
                PocketCount(label: "Review", value: "3", tint: AtlasPalette.coral.opacity(0.52))
                PocketCount(label: "Map Stamps", value: "18", tint: AtlasPalette.mint)
                PocketCount(label: "Failed", value: "2", tint: AtlasPalette.coral.opacity(0.35))
            }
            .placed(x: 10, y: 216, width: 382, height: 43)
            .accessibilityIdentifier("prototype.saves.counts")

            SavesTickets()
                .placed(x: 10, y: 278, width: 382, height: 333)
                .accessibilityIdentifier("prototype.saves.tickets")

            SavesEnvelopePanel()
                .placed(x: 0, y: 568, width: 402, height: 207)
                .accessibilityIdentifier("prototype.saves.envelope")
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prototype.saves")
    }
}

private struct SavesTitleBlock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("YOUR PLACE MEMORY")
                .font(AtlasType.strong(11))
                .tracking(1.15)
                .foregroundStyle(AtlasPalette.muted)

            Text("Saves")
                .font(AtlasType.strong(34))
                .foregroundStyle(AtlasPalette.forest)

            Text("Clues you’ve saved from links and notes.")
                .font(AtlasType.body(15))
                .foregroundStyle(AtlasPalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PocketCount: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
            Text(value)
                .font(AtlasType.strong(16))
                .frame(width: 25, height: 25)
                .background(tint, in: Circle())
        }
        .font(AtlasType.display(14))
        .foregroundStyle(AtlasPalette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AtlasPalette.line.opacity(0.30), lineWidth: 1)
        }
    }
}

private struct SavesEnvelopePanel: View {
    private let sealInk = Color(red: 0.66, green: 0.32, blue: 0.22)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("SavesEnvelope")
                .resizable()
                .scaledToFill()
                .clipped()

            Text("Full review queue")
                .font(AtlasType.editorial(20))
                .foregroundStyle(AtlasPalette.ink)
                .position(x: 181, y: 82)

            Path { path in
                path.move(to: CGPoint(x: 111, y: 105))
                path.addLine(to: CGPoint(x: 253, y: 105))
            }
            .stroke(
                AtlasPalette.line.opacity(0.68),
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
            )

            VStack(spacing: -3) {
                Text("3")
                    .font(AtlasType.editorial(29))
                Text("need your\nreview")
                    .font(AtlasType.regular(10))
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)
            }
            .foregroundStyle(sealInk)
            .frame(width: 58, height: 78)
            .position(x: 333, y: 91)
        }
        .frame(width: 402, height: 207)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Full review queue, 3 need your review")
    }
}

private struct SavesTickets: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            ReviewTicket(
                kind: "REVIEW CANDIDATE",
                name: "Tsukiji Outer Market",
                detail: "From Xiaohongshu",
                action: "Review",
                tint: AtlasPalette.sky,
                icon: "camera"
            )
            .placed(x: 0, y: 0, width: 382, height: 111)

            ReviewTicket(
                kind: "REVIEW CANDIDATE",
                name: "Koffee Mameya",
                detail: "From Instagram",
                action: "Review",
                tint: AtlasPalette.sky,
                icon: "camera"
            )
            .placed(x: 0, y: 107, width: 382, height: 111)

            ReviewTicket(
                kind: "SOURCE CLUE",
                name: "Yasaka Pagoda",
                detail: "Missing exact place",
                action: "Find exact",
                tint: Color(red: 1.0, green: 0.79, blue: 0.72),
                icon: "magnifyingglass"
            )
            .placed(x: 0, y: 210, width: 382, height: 118)
        }
    }
}

private struct ReviewTicket: View {
    let kind: String
    let name: String
    let detail: String
    let action: String
    let tint: Color
    let icon: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScallopedRectangle(depth: 3, pitch: 10)
                .fill(tint.opacity(0.94))
                .shadow(color: AtlasPalette.ink.opacity(0.06), radius: 4, y: 2)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AtlasPalette.paper)
                .padding(5)

            PerforatedMedallion(systemName: icon, tint: tint)
                .position(x: 47, y: 55)

            VStack(alignment: .leading, spacing: 1) {
                Text(kind)
                    .font(AtlasType.strong(11))
                    .tracking(0.6)
                    .foregroundStyle(
                        kind == "SOURCE CLUE" ? AtlasPalette.coral : Color(red: 0.10, green: 0.48, blue: 0.70)
                    )
                Text(name)
                    .font(AtlasType.strong(19))
                    .foregroundStyle(AtlasPalette.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(AtlasType.body(13))
                    .foregroundStyle(AtlasPalette.muted)
            }
            .frame(width: 190, alignment: .leading)
            .position(x: 181, y: 55)

            Button(action: {}) {
                Text(action)
                    .font(AtlasType.display(14))
                    .foregroundStyle(AtlasPalette.ink)
                    .frame(width: action == "Find exact" ? 82 : 68, height: 38)
                    .background(tint.opacity(0.84), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AtlasPalette.ink.opacity(0.22), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: action == "Find exact" ? 88 : 74, height: 44)
                .position(x: action == "Find exact" ? 313 : 316, y: 55)
                .accessibilityLabel("\(action) \(name)")
                .accessibilityHint("Prototype action")
                .accessibilityIdentifier(
                    "prototype.saves.\(action == "Find exact" ? "findExact" : "review")."
                        + name.lowercased().replacingOccurrences(of: " ", with: "-")
                )
        }
    }
}

struct TripPlanScreen: View {
    let onBack: () -> Void

    private let stops = [
        PlanStop(
            name: "Tsukiji Outer Market",
            time: "9:00 AM",
            note: "Seafood stalls & breakfast",
            image: "TsukijiThumbnail",
            imageHeight: 78
        ),
        PlanStop(
            name: "Koffee Mameya",
            time: "11:30 AM",
            note: "Coffee & people watching",
            image: "KoffeeMameyaThumbnail",
            imageHeight: 82
        ),
        PlanStop(
            name: "teamLab Borderless",
            time: "2:30 PM",
            note: "Immersive digital art",
            image: "TeamLabThumbnail",
            imageHeight: 83
        ),
        PlanStop(
            name: "Shibuya Sky",
            time: "6:30 PM",
            note: "Sunset city views",
            image: "ShibuyaSkyThumbnail",
            imageHeight: 84
        ),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            TripHeader(onBack: onBack)
                .placed(x: 0, y: 48, width: 402, height: 54)
                .accessibilityIdentifier("prototype.plan.header")

            DayTabs()
                .placed(x: 0, y: 102, width: 402, height: 47)
                .accessibilityIdentifier("prototype.plan.dayTabs")

            PlanTitleBlock()
                .placed(x: 6, y: 168, width: 390, height: 58)

            Image("PlanRouteRibbon")
                .resizable()
                .scaledToFill()
                .clipped()
                .placed(x: 0, y: 229, width: 64, height: 493)
                .accessibilityLabel("Day 2 route")
                .accessibilityIdentifier("prototype.plan.route")

            PlanStops(stops: stops)
                .placed(x: 61, y: 238, width: 332, height: 478)
                .accessibilityIdentifier("prototype.plan.stops")

            Button(action: {}) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18, weight: .regular))
                    Text("Add stop")
                        .font(AtlasType.display(16))
                }
                .foregroundStyle(AtlasPalette.ink)
                .frame(width: 140, height: 40)
                .background(AtlasPalette.mint, in: Capsule())
                .overlay {
                    Capsule().stroke(AtlasPalette.forest.opacity(0.30), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .placed(x: 122, y: 728, width: 140, height: 40)
            .accessibilityIdentifier("prototype.action.addStop")
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prototype.plan")
    }
}

private struct PlanStop {
    let name: String
    let time: String
    let note: String
    let image: String
    let imageHeight: CGFloat
}

private struct TripHeader: View {
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(AtlasPalette.ink)
                    .frame(width: 40, height: 40)
                    .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(AtlasPalette.line.opacity(0.32), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .position(x: 22, y: 27)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("prototype.trip.back")

            Text("Tokyo Weekend")
                .font(AtlasType.strong(23))
                .foregroundStyle(AtlasPalette.forest)

            MemoMark(size: 48)
                .position(x: 375, y: 26)
        }
    }
}

private struct DayTabs: View {
    var body: some View {
        HStack(spacing: 8) {
            DayTab(title: "Day 1", tint: AtlasPalette.paper, selected: false)
            DayTab(title: "Day 2", tint: AtlasPalette.mint, selected: true)
            DayTab(title: "Day 3", tint: AtlasPalette.lavender, selected: false)
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtlasPalette.line.opacity(0.26))
                .frame(height: 1)
        }
    }
}

private struct DayTab: View {
    let title: String
    let tint: Color
    let selected: Bool

    var body: some View {
        Text(title)
            .font(selected ? AtlasType.strong(15) : AtlasType.body(15))
            .foregroundStyle(AtlasPalette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 13,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 13
                )
            )
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 13,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 13
                )
                .stroke(AtlasPalette.line.opacity(selected ? 0.32 : 0.24), lineWidth: 1)
            }
    }
}

private struct PlanTitleBlock: View {
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                Text("TUESDAY, OCTOBER 13")
                    .font(AtlasType.strong(11))
                    .tracking(0.8)
                    .foregroundStyle(AtlasPalette.muted)

                Text("Tokyo highlights")
                    .font(AtlasType.strong(26))
                    .foregroundStyle(AtlasPalette.forest)
            }

            Spacer()

            Text("4 stops")
                .font(AtlasType.display(14))
                .foregroundStyle(AtlasPalette.ink)
                .frame(width: 70, height: 29)
                .background(AtlasPalette.mint, in: Capsule())
                .overlay {
                    Capsule().stroke(AtlasPalette.forest.opacity(0.24), lineWidth: 1)
                }
        }
    }
}

private struct PlanStops: View {
    let stops: [PlanStop]
    private let frames: [CGRect] = [
        CGRect(x: 0, y: 0, width: 332, height: 101),
        CGRect(x: 0, y: 122, width: 332, height: 105),
        CGRect(x: 0, y: 250, width: 332, height: 105),
        CGRect(x: 0, y: 376, width: 332, height: 102),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                ItineraryStop(stop: stop)
                    .placed(
                        x: frames[index].minX,
                        y: frames[index].minY,
                        width: frames[index].width,
                        height: frames[index].height
                    )
            }
        }
    }
}

private struct ItineraryStop: View {
    let stop: PlanStop

    var body: some View {
        HStack(spacing: 18) {
            Image(stop.image)
                .resizable()
                .scaledToFit()
                .frame(width: 74, height: stop.imageHeight)

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(AtlasType.strong(17))
                    .foregroundStyle(AtlasPalette.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .regular))
                    Text(stop.time)
                        .font(AtlasType.body(13))
                }
                .foregroundStyle(AtlasPalette.muted)

                Text(stop.note)
                    .font(AtlasType.regular(13))
                    .foregroundStyle(AtlasPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AtlasPalette.ink)
        }
        .padding(.leading, 11)
        .padding(.trailing, 16)
        .background(AtlasPalette.paper.opacity(0.97), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AtlasPalette.line.opacity(0.24), lineWidth: 1)
        }
    }
}

struct TripAtlasMapScreen: View {
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            TripHeader(onBack: onBack)
                .placed(x: 0, y: 48, width: 402, height: 54)
                .accessibilityIdentifier("prototype.trip.map.header")

            Image("MapAtlasScene")
                .resizable()
                .scaledToFill()
                .clipped()
                .placed(x: 0, y: 102, width: 402, height: 450)
                .accessibilityLabel("Tokyo Weekend route map")
                .accessibilityIdentifier("prototype.trip.map.atlas")

            HStack(spacing: 7) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 14, weight: .regular))
                Text("DAY 2 · 4 STOPS")
                    .font(AtlasType.display(13))
            }
            .foregroundStyle(AtlasPalette.ink)
            .frame(width: 145, height: 31)
            .background(AtlasPalette.mint, in: Capsule())
            .overlay {
                Capsule().stroke(AtlasPalette.forest.opacity(0.24), lineWidth: 1)
            }
            .placed(x: 128, y: 114, width: 145, height: 31)
            .accessibilityLabel("Day 2, 4 stops")

            TripMapPlaceCard()
                .placed(x: 15, y: 550, width: 372, height: 226)
                .accessibilityIdentifier("prototype.trip.map.placeCard")
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prototype.trip.map")
    }
}

private struct TripMapPlaceCard: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AtlasPalette.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AtlasPalette.line.opacity(0.32), lineWidth: 1)
                }
                .shadow(color: AtlasPalette.ink.opacity(0.06), radius: 7, y: 2)

            RoundStamp(text: "2", style: .tripStop)
                .position(x: 44, y: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text("STOP 2 · 11:30 AM")
                    .font(AtlasType.display(11))
                    .tracking(0.7)
                    .foregroundStyle(AtlasPalette.muted)

                Text("Koffee Mameya")
                    .font(AtlasType.strong(23))
                    .foregroundStyle(AtlasPalette.forest)
            }
            .position(x: 176, y: 40)

            HStack(spacing: 6) {
                Image(systemName: "star.circle")
                    .font(.system(size: 13, weight: .regular))
                Text("Confirmed Map Stamp")
                    .font(AtlasType.display(13))
            }
            .foregroundStyle(AtlasPalette.ink)
            .frame(width: 183, height: 30)
            .background(AtlasPalette.mint, in: Capsule())
            .overlay {
                Capsule().stroke(AtlasPalette.forest.opacity(0.20), lineWidth: 1)
            }
            .position(x: 168, y: 91)

            Text("Tsukiji Outer Market  →  Koffee Mameya  →  teamLab")
                .font(AtlasType.body(13))
                .foregroundStyle(AtlasPalette.muted)
                .lineLimit(1)
                .position(x: 186, y: 132)

            Text("Next stop · teamLab Borderless at 2:30 PM")
                .font(AtlasType.regular(14))
                .foregroundStyle(AtlasPalette.muted)
                .position(x: 171, y: 158)

            Button(action: {}) {
                HStack(spacing: 10) {
                    Text("Open stop")
                        .font(AtlasType.strong(17))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .regular))
                }
                .foregroundStyle(.white)
                .frame(width: 160, height: 42)
                .background(AtlasPalette.coral, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .position(x: 95, y: 198)
            .accessibilityIdentifier("prototype.action.openTripStop")
        }
    }
}

struct TripInboxPlaceholderScreen: View {
    let onBack: () -> Void

    var body: some View {
        TripPrototypePlaceholder(
            onBack: onBack,
            icon: "tray.full",
            eyebrow: "TRIP INBOX",
            title: "Trip Inbox",
            message: "Trip-only links and review candidates will appear here.",
            note: "Not wired in this visual prototype",
            tint: AtlasPalette.sky,
            identifier: "prototype.trip.inbox"
        )
    }
}

struct TripSharePlaceholderScreen: View {
    let onBack: () -> Void

    var body: some View {
        TripPrototypePlaceholder(
            onBack: onBack,
            icon: "square.and.arrow.up",
            eyebrow: "TRIP SHARE",
            title: "Share this Trip",
            message: "SAV-E link and KML export will appear here.",
            note: "Not wired in this visual prototype",
            tint: AtlasPalette.lavender,
            identifier: "prototype.trip.share"
        )
    }
}

private struct TripPrototypePlaceholder: View {
    let onBack: () -> Void
    let icon: String
    let eyebrow: String
    let title: String
    let message: String
    let note: String
    let tint: Color
    let identifier: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            TripHeader(onBack: onBack)
                .placed(x: 0, y: 48, width: 402, height: 54)
                .accessibilityIdentifier("\(identifier).header")

            VStack(spacing: 18) {
                MemoMark(size: 88)
                    .frame(height: 104)

                Image(systemName: icon)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(AtlasPalette.forest)
                    .frame(width: 68, height: 68)
                    .background(tint, in: Circle())

                VStack(spacing: 7) {
                    Text(eyebrow)
                        .font(AtlasType.display(12))
                        .tracking(0.9)
                        .foregroundStyle(AtlasPalette.muted)

                    Text(title)
                        .font(AtlasType.strong(28))
                        .foregroundStyle(AtlasPalette.forest)

                    Text(message)
                        .font(AtlasType.regular(16))
                        .foregroundStyle(AtlasPalette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 285)
                }

                Text(note)
                    .font(AtlasType.display(13))
                    .foregroundStyle(AtlasPalette.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(tint.opacity(0.72), in: Capsule())
                    .overlay {
                        Capsule().stroke(AtlasPalette.forest.opacity(0.22), lineWidth: 1)
                    }
            }
            .frame(width: 350, height: 480)
            .background(AtlasPalette.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AtlasPalette.line.opacity(0.28), lineWidth: 1)
            }
            .placed(x: 26, y: 170, width: 350, height: 480)
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

struct RootAtlasMapScreen: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            Image("MapAtlasScene")
                .resizable()
                .scaledToFill()
                .clipped()
                .placed(x: 0, y: 91, width: 402, height: 480)
                .accessibilityLabel("Illustrated Tokyo route map")
                .accessibilityIdentifier("prototype.map.atlas")

            BrandHeader {
                HStack(spacing: 7) {
                    Image(systemName: "star.circle")
                        .font(.system(size: 16, weight: .regular))
                    Text("18 Map Stamps")
                        .font(AtlasType.display(14))
                }
                .foregroundStyle(AtlasPalette.ink)
                .frame(width: 157, height: 34)
                .background(AtlasPalette.mint, in: Capsule())
                .overlay {
                    Capsule().stroke(AtlasPalette.forest.opacity(0.24), lineWidth: 1)
                }
            }
            .background(AtlasPalette.canvas.opacity(0.96))
            .placed(x: 0, y: 48, width: 402, height: 50)
            .accessibilityIdentifier("prototype.map.header")

            PlaceAtlasCard()
                .placed(x: 15, y: 550, width: 372, height: 238)
                .accessibilityIdentifier("prototype.map.placeCard")
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prototype.map")
    }
}

private struct PlaceAtlasCard: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AtlasPalette.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AtlasPalette.line.opacity(0.32), lineWidth: 1)
                }
                .shadow(color: AtlasPalette.ink.opacity(0.06), radius: 7, y: 2)

            RoundStamp(text: "2", style: .tripStop)
                .position(x: 44, y: 42)

            Text("Koffee Mameya")
                .font(AtlasType.strong(23))
                .foregroundStyle(AtlasPalette.forest)
                .position(x: 170, y: 33)

            Text("Shibuya")
                .font(AtlasType.body(14))
                .foregroundStyle(AtlasPalette.muted)
                .position(x: 111, y: 62)

            HStack(spacing: 6) {
                Image(systemName: "star.circle")
                    .font(.system(size: 13, weight: .regular))
                Text("Confirmed Map Stamp")
                    .font(AtlasType.display(13))
            }
            .foregroundStyle(AtlasPalette.ink)
            .frame(width: 183, height: 30)
            .background(AtlasPalette.mint, in: Capsule())
            .overlay {
                Capsule().stroke(AtlasPalette.forest.opacity(0.20), lineWidth: 1)
            }
            .position(x: 168, y: 91)

            Text("Cozy coffee shop known for house\nblend and quiet corners.")
                .font(AtlasType.regular(14))
                .foregroundStyle(AtlasPalette.muted)
                .lineSpacing(3)
                .position(x: 182, y: 139)

            Button(action: {}) {
                HStack {
                    Spacer()
                    Text("Open details")
                        .font(AtlasType.strong(17))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .regular))
                        .padding(.trailing, 14)
                }
                .foregroundStyle(.white)
                .frame(width: 226, height: 42)
                .background(AtlasPalette.coral, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .position(x: 133, y: 202)
            .accessibilityIdentifier("prototype.action.openDetails")

            Button(action: {}) {
                Image(systemName: "bookmark")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AtlasPalette.forest)
                    .frame(width: 49, height: 42)
                    .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AtlasPalette.line.opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .position(x: 328, y: 202)
            .accessibilityIdentifier("prototype.action.bookmark")
        }
    }
}
