import SwiftUI

struct HomeAtlasScreen: View {
    var body: some View {
        ZStack {
            DottedCanvas()

            VStack(spacing: 0) {
                BrandHeader {
                    Button(action: {}) {
                        Label("Paste a link", systemImage: "link.badge.plus")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AtlasPalette.forest)
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(AtlasPalette.paper, in: Capsule())
                            .overlay { Capsule().stroke(AtlasPalette.ink.opacity(0.18), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }

                ZStack(alignment: .bottom) {
                    AtlasMapArt(variant: .home)

                    VStack(spacing: 0) {
                        MemoMark(size: 78)
                            .offset(y: 16)
                            .zIndex(1)

                        VStack(spacing: 9) {
                            Text("3 clues need your help")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(AtlasPalette.forest)

                            Text("Review and decide what’s worth saving.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasPalette.muted)

                            Button(action: {}) {
                                HStack {
                                    Text("Review clues")
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .frame(height: 40)
                                .background(AtlasPalette.coral, in: RoundedRectangle(cornerRadius: 11))
                            }
                            .buttonStyle(.plain)

                            HStack(spacing: 0) {
                                HomeMetric(value: "3", label: "to review", icon: "clock.fill", tint: AtlasPalette.lavender)
                                Divider().frame(height: 30)
                                HomeMetric(value: "18", label: "Map Stamps", icon: "arrow.up.right", tint: AtlasPalette.mint)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                        .atlasPaper(radius: 18, shadow: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                .frame(height: 360)
                .padding(.horizontal, 12)

                TripPreviewRow()
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                RecentStampRows()
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                Spacer(minLength: 4)
            }
        }
        .accessibilityIdentifier("prototype.home")
    }
}

private struct HomeMetric: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .background(tint, in: Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasPalette.muted)
            }
            .foregroundStyle(AtlasPalette.forest)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TripPreviewRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("NEXT UP")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(AtlasPalette.muted)
                Spacer()
                Text("Day 2 of 3")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(AtlasPalette.forest)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AtlasPalette.lavender, in: Capsule())
            }

            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(AtlasPalette.forest)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tokyo Weekend")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(AtlasPalette.forest)
                    Text("4 stops planned · Next: Tsukiji · 9:00 AM")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasPalette.muted)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption.bold())
                    .foregroundStyle(AtlasPalette.muted)
            }
        }
    }
}

private struct RecentStampRows: View {
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text("RECENT MAP STAMPS")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(AtlasPalette.muted)
                Spacer()
                Text("See all")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AtlasPalette.ink)
            }

            StampRow(name: "Shibuya Backstreets", area: "Tokyo", day: "Today")
            StampRow(name: "Koffee Mameya", area: "Shibuya", day: "Yesterday")
        }
    }
}

private struct StampRow: View {
    let name: String
    let area: String
    let day: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(AtlasPalette.forest)
                .frame(width: 29, height: 29)
                .background(AtlasPalette.mint, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AtlasPalette.ink)
                Text("\(area) · Confirmed")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasPalette.muted)
            }
            Spacer()
            Text(day)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasPalette.muted)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(AtlasPalette.muted)
        }
        .frame(height: 34)
    }
}

struct SavesPocketScreen: View {
    var body: some View {
        ZStack {
            DottedCanvas()

            VStack(spacing: 0) {
                BrandHeader {
                    Button(action: {}) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AtlasPalette.forest)
                            .frame(width: 38, height: 38)
                            .background(AtlasPalette.honey.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("YOUR PLACE MEMORY")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.3)
                            .foregroundStyle(AtlasPalette.muted)
                        Text("Saves")
                            .font(.system(size: 29, weight: .black, design: .rounded))
                            .foregroundStyle(AtlasPalette.forest)
                        Text("Clues you’ve saved from links and notes.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasPalette.muted)
                    }
                    Spacer()
                    MemoMark(size: 83)
                }
                .padding(.horizontal, 18)
                .frame(height: 105)

                HStack(spacing: 7) {
                    PocketCount(label: "Review", value: "3", tint: AtlasPalette.coral.opacity(0.36))
                    PocketCount(label: "Map Stamps", value: "18", tint: AtlasPalette.mint)
                    PocketCount(label: "Failed", value: "2", tint: AtlasPalette.coral.opacity(0.23))
                }
                .padding(.horizontal, 18)

                ZStack(alignment: .top) {
                    EnvelopePocket()
                        .padding(.top, 250)

                    VStack(spacing: -8) {
                        ReviewTicket(
                            kind: "REVIEW CANDIDATE",
                            name: "Tsukiji Outer Market",
                            detail: "From Xiaohongshu",
                            action: "Review",
                            tint: AtlasPalette.sky,
                            icon: "camera.fill"
                        )
                        ReviewTicket(
                            kind: "REVIEW CANDIDATE",
                            name: "Koffee Mameya",
                            detail: "From Instagram",
                            action: "Review",
                            tint: AtlasPalette.sky,
                            icon: "camera.fill"
                        )
                        ReviewTicket(
                            kind: "SOURCE CLUE",
                            name: "Yasaka Pagoda",
                            detail: "Missing exact place",
                            action: "Find exact",
                            tint: AtlasPalette.coral.opacity(0.30),
                            icon: "magnifyingglass"
                        )
                    }
                    .padding(.horizontal, 18)
                }
                .frame(height: 480)

                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("prototype.saves")
    }
}

private struct PocketCount: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
            Text(value)
                .fontWeight(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(tint, in: Capsule())
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(AtlasPalette.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(AtlasPalette.ink.opacity(0.13), lineWidth: 1)
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
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AtlasPalette.forest)
                .frame(width: 43, height: 43)
                .background(tint, in: ScallopBadge())

            VStack(alignment: .leading, spacing: 2) {
                Text(kind)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(kind == "SOURCE CLUE" ? AtlasPalette.coral : AtlasPalette.forest)
                Text(name)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(AtlasPalette.ink)
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasPalette.muted)
            }

            Spacer()

            Text(action)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AtlasPalette.forest)
                .padding(.horizontal, 10)
                .frame(height: 31)
                .background(tint, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(AtlasPalette.forest.opacity(0.24), lineWidth: 1)
                }
        }
        .padding(.horizontal, 12)
        .frame(height: 92)
        .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    kind == "SOURCE CLUE" ? AtlasPalette.coral : AtlasPalette.sky,
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                )
        }
        .shadow(color: AtlasPalette.ink.opacity(0.06), radius: 6, y: 3)
    }
}

private struct ScallopBadge: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: 13)
    }
}

private struct EnvelopePocket: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AtlasPalette.kraft)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AtlasPalette.ink.opacity(0.25), lineWidth: 1)
                }

            EnvelopeFlap()
                .fill(AtlasPalette.kraft.opacity(0.78))
                .overlay {
                    EnvelopeFlap()
                        .stroke(AtlasPalette.ink.opacity(0.16), lineWidth: 1)
                }

            VStack(spacing: 13) {
                HStack {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Full review queue")
                        .font(.system(size: 18, weight: .black, design: .serif))
                    Spacer()
                    VStack(spacing: 0) {
                        Text("3")
                            .font(.system(size: 23, weight: .black, design: .rounded))
                        Text("need your\nreview")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(AtlasPalette.coral)
                    .frame(width: 58, height: 58)
                    .background(AtlasPalette.paper.opacity(0.55), in: Circle())
                    .overlay {
                        Circle().stroke(
                            AtlasPalette.coral.opacity(0.75),
                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                        )
                    }
                }

                HStack {
                    Image(systemName: "airplane")
                    Rectangle()
                        .fill(AtlasPalette.ink.opacity(0.24))
                        .frame(height: 1)
                    Image(systemName: "mappin.and.ellipse")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AtlasPalette.coral.opacity(0.75))
            }
            .foregroundStyle(AtlasPalette.forest)
            .padding(18)
        }
        .frame(height: 205)
        .padding(.horizontal, 6)
    }
}

private struct EnvelopeFlap: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.closeSubpath()
        return path
    }
}

struct TripPlanScreen: View {
    let onBack: () -> Void

    private let stops = [
        ("Tsukiji Outer Market", "9:00 AM", "Seafood stalls & breakfast", "ferry.fill", AtlasPalette.sky),
        ("Koffee Mameya", "11:30 AM", "Coffee & people watching", "cup.and.heat.waves.fill", AtlasPalette.kraft),
        ("teamLab Borderless", "2:30 PM", "Immersive digital art", "sparkles", AtlasPalette.lavender),
        ("Shibuya Sky", "6:30 PM", "Sunset city views", "sun.max.fill", AtlasPalette.mint),
    ]

    var body: some View {
        ZStack {
            DottedCanvas()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AtlasPalette.ink)
                            .frame(width: 38, height: 38)
                            .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AtlasPalette.ink.opacity(0.16), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("prototype.trip.back")
                    .accessibilityLabel("Back")

                    Spacer()
                    Text("Tokyo Weekend")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(AtlasPalette.forest)
                    Spacer()
                    MemoMark(size: 39)
                }
                .frame(height: 52)
                .padding(.horizontal, 18)

                HStack(spacing: 0) {
                    DayTab(title: "Day 1", tint: AtlasPalette.paper, selected: false)
                    DayTab(title: "Day 2", tint: AtlasPalette.mint, selected: true)
                    DayTab(title: "Day 3", tint: AtlasPalette.lavender, selected: false)
                }
                .padding(.horizontal, 18)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TUESDAY, OCTOBER 13")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(AtlasPalette.muted)
                        Text("Tokyo highlights")
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .foregroundStyle(AtlasPalette.forest)
                    }
                    Spacer()
                    Text("4 stops")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasPalette.forest)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AtlasPalette.mint, in: Capsule())
                }
                .padding(.horizontal, 18)
                .padding(.top, 15)
                .padding(.bottom, 8)

                ZStack(alignment: .topLeading) {
                    RouteRibbon()
                        .frame(width: 74)
                        .padding(.leading, 17)

                    VStack(spacing: 9) {
                        ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                            ItineraryStop(
                                number: index + 1,
                                name: stop.0,
                                time: stop.1,
                                note: stop.2,
                                icon: stop.3,
                                tint: stop.4
                            )
                        }
                    }
                }
                .padding(.horizontal, 18)

                Button(action: {}) {
                    Label("Add stop", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasPalette.forest)
                        .padding(.horizontal, 18)
                        .frame(height: 37)
                        .background(AtlasPalette.mint, in: Capsule())
                        .overlay { Capsule().stroke(AtlasPalette.forest.opacity(0.18), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .padding(.top, 10)

                Spacer(minLength: 2)
            }
        }
        .accessibilityIdentifier("prototype.plan")
    }
}

private struct DayTab: View {
    let title: String
    let tint: Color
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: selected ? .black : .medium, design: .rounded))
            .foregroundStyle(AtlasPalette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(tint)
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(AtlasPalette.ink.opacity(selected ? 0.26 : 0.14), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

private struct ItineraryStop: View {
    let number: Int
    let name: String
    let time: String
    let note: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(AtlasPalette.ink)
                .frame(width: 34, height: 34)
                .background(AtlasPalette.coral.opacity(0.80), in: Circle())
                .overlay { Circle().stroke(AtlasPalette.coral, lineWidth: 1) }

            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AtlasPalette.forest)
                .frame(width: 54, height: 54)
                .background(tint, in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(AtlasPalette.ink)
                    .lineLimit(1)
                Label(time, systemImage: "clock")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasPalette.muted)
                Text(note)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AtlasPalette.muted)
        }
        .padding(.horizontal, 10)
        .frame(height: 76)
        .background(AtlasPalette.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(AtlasPalette.ink.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct RouteRibbon: View {
    var body: some View {
        Canvas { context, size in
            var ribbon = Path()
            ribbon.move(to: CGPoint(x: size.width * 0.55, y: 0))
            ribbon.addCurve(
                to: CGPoint(x: size.width * 0.44, y: size.height),
                control1: CGPoint(x: 0, y: size.height * 0.28),
                control2: CGPoint(x: size.width, y: size.height * 0.70)
            )
            context.stroke(ribbon, with: .color(AtlasPalette.sky.opacity(0.55)), lineWidth: 42)
            context.stroke(
                ribbon,
                with: .color(AtlasPalette.routeInk),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 5])
            )
        }
    }
}

struct RootAtlasMapScreen: View {
    var body: some View {
        ZStack {
            AtlasMapArt(variant: .full)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                BrandHeader {
                    Label("18 Map Stamps", systemImage: "star.circle.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasPalette.forest)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(AtlasPalette.mint, in: Capsule())
                        .overlay { Capsule().stroke(AtlasPalette.forest.opacity(0.15), lineWidth: 1) }
                }
                .background(AtlasPalette.canvas.opacity(0.90))

                Spacer()

                ZStack(alignment: .topTrailing) {
                    PlaceAtlasCard()
                    MemoMark(size: 76)
                        .offset(x: -20, y: -48)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }
        }
        .accessibilityIdentifier("prototype.map")
    }
}

private struct PlaceAtlasCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                AtlasRoutePin(number: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Koffee Mameya")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(AtlasPalette.forest)
                    Text("Shibuya")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasPalette.muted)
                }
                Spacer()
            }

            Label("Confirmed Map Stamp", systemImage: "checkmark.seal.fill")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(AtlasPalette.forest)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AtlasPalette.mint, in: Capsule())

            Text("Cozy coffee shop known for house blend and quiet corners.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasPalette.muted)

            HStack(spacing: 9) {
                Button(action: {}) {
                    HStack {
                        Text("Open details")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(AtlasPalette.coral, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button(action: {}) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AtlasPalette.forest)
                        .frame(width: 40, height: 38)
                        .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AtlasPalette.ink.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .atlasPaper(radius: 21, shadow: true)
    }
}
