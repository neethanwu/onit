import SwiftUI

struct JobListView: View {
    let store: JobStore
    let now: Date
    let onSelect: (Job) -> Void

    private let rowHeight: CGFloat = 46
    private let maxVisibleRows = 7

    var body: some View {
        let jobs = store.visibleJobs
        VStack(spacing: 0) {
            header
                .zIndex(1)
            UpdateCard(updates: updates)
                .padding(.horizontal, 6)
                .padding(.bottom, updates.phase == .idle ? 0 : 6)
                .animation(.onitSpring, value: updates.phase)
            if jobs.isEmpty {
                EmptyListView(store: store)
            } else {
                if let next = store.nextUp(now: now) {
                    NextUpCard(job: next.job, date: next.date, now: now)
                        .padding(.horizontal, 6)
                }
                list(jobs)
            }
        }
    }

    @Environment(\.notchStyle) private var notchStyle
    @Environment(\.notchModel) private var notchModel
    @Environment(Updates.self) private var updates

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if notchStyle {
                // The notch draws Bead itself and flies it here from the wing; this only holds its place.
                Button {
                    notchModel?.beadPokes += 1
                } label: {
                    Color.clear
                        .frame(width: NotchModel.headerBeadSize, height: NotchModel.headerBeadSize)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(GeometryReader { proxy in
                        Color.clear.preference(key: BeadSlotKey.self, value: proxy.frame(in: .named(NotchModel.space)))
                    })
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                subtitle
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                RefreshButton(store: store)
                MoreMenu(store: store)
            }
        }
        .padding(.horizontal, Metrics.edge)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// The headline says how things are; the count goes underneath.
    private var title: String {
        switch store.overallState {
        case .empty: return "onit"
        case .failed: return store.failedCount == 1 ? "1 task failed" : "\(store.failedCount) tasks failed"
        case .headsUp: return store.overlapCount == 1 ? "1 task needs a look" : "\(store.overlapCount) tasks need a look"
        case .running: return store.activeRunCount == 1 ? "1 task running" : "\(store.activeRunCount) tasks running"
        case .ok: return "All good"
        }
    }

    private var subtitle: Text {
        let count = store.activeCount
        if store.jobs.isEmpty { return Text("Looking for tasks…") }
        let watching = count == 0 ? "Nothing to watch" : count == 1 ? "Watching 1 task" : "Watching \(count) tasks"
        // Say how many are hidden whenever that explains what's on screen: an empty list, or hidden rows shown below.
        let hidden = store.hiddenCount
        guard hidden > 0, count == 0 || store.showHidden else { return Text(watching) }
        return Text("\(watching) · \(hidden) hidden")
    }

    @ViewBuilder
    private func list(_ jobs: [Job]) -> some View {
        // Hidden tasks, when shown, sit in their own group below the ones onit watches.
        let watched = jobs.filter { !$0.isHidden }
        let hidden = jobs.filter(\.isHidden)
        let rows = VStack(alignment: .leading, spacing: 0) {
            if !watched.isEmpty {
                rowStack(watched)
            }
            if !hidden.isEmpty {
                Text("Hidden")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.top, watched.isEmpty ? 4 : 10)
                    .padding(.bottom, 4)
                rowStack(hidden)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 8)

        if jobs.count > maxVisibleRows {
            ScrollView { rows }
                .frame(height: rowHeight * CGFloat(maxVisibleRows) + 14)
                .scrollIndicators(.automatic)
        } else {
            rows
        }
    }
}

extension JobListView {
    fileprivate func rowStack(_ jobs: [Job]) -> some View {
        FluidHoverStack(items: jobs, onActivate: onSelect) { job, _ in
            JobRowView(store: store, job: job, now: now) { onSelect(job) }
        }
    }
}

struct NextUpCard: View {
    let job: Job
    let date: Date
    let now: Date

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next up")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
                Text(job.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(TimeText.until(date, now: now))
                    .font(.system(size: 14, weight: .medium))
                    .contentTransition(.numericText())
                Text("at \(TimeText.clock(date))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .animation(.easeOut(duration: 0.25), value: TimeText.until(date, now: now))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .card()
    }
}

struct MoreMenu: View {
    @Bindable var store: JobStore
    @Environment(DisplayController.self) private var display
    @Environment(Updates.self) private var updates
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MoreButton(id: "app") { entries }
    }

    private var entries: [MenuEntry] {
        var entries: [MenuEntry] = []
        if display.notchAvailable {
            let toNotch = display.preference == .menuBar
            entries.append(.item(
                title: toNotch ? "Show in Notch" : "Show in Menu Bar",
                systemImage: toNotch ? "rectangle.topthird.inset.filled" : "menubar.rectangle"
            ) {
                // Removing the menu bar icon doesn't close its panel, so close it before the notch takes over.
                if toNotch { dismiss() }
                display.preference = toNotch ? .notch : .menuBar
            })
            entries.append(.divider(id: "display"))
        }
        entries.append(.item(title: "Show Hidden Tasks (\(store.hiddenCount))", systemImage: "eye.slash", checked: store.showHidden) {
            store.showHidden.toggle()
        })
        entries.append(.item(title: "Open at Login", systemImage: "power", checked: store.launchesAtLogin) {
            store.launchesAtLogin.toggle()
        })
        entries.append(.divider(id: "about"))
        entries.append(.item(title: "Check for Updates…", systemImage: "arrow.down.circle") {
            updates.check()
        })
        entries.append(.item(title: "About onit", systemImage: "info.circle") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        entries.append(.divider(id: "quit"))
        entries.append(.item(title: "Quit onit", systemImage: "xmark.circle", shortcut: "q") {
            NSApp.terminate(nil)
        })
        return entries
    }
}

/// One full turn per refresh, however fast the refresh is.
struct RefreshButton: View {
    let store: JobStore
    @State private var spins = 0

    var body: some View {
        Button {
            spins += 1
            Task { await store.refresh() }
        } label: {
            // The system's own rotate effect for this symbol: the arrow turns around the circle's
            // center with an eased start and stop, rather than the whole glyph wobbling.
            Image(systemName: "arrow.clockwise")
                .symbolEffect(.rotate.clockwise.byLayer, options: .nonRepeating, value: spins)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(GlassCircleButtonStyle())
        .help("Refresh")
    }
}

struct EmptyListView: View {
    @Bindable var store: JobStore

    var body: some View {
        VStack(spacing: 14) {
            OrbitMark()
                .frame(width: 52, height: 52)
            VStack(spacing: 5) {
                Text("Nothing scheduled yet")
                    .font(.system(size: 15, weight: .semibold))
                Text("When you or your agent sets up something that runs on a schedule, it shows up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.hiddenCount > 0 {
                Button {
                    store.showHidden = true
                } label: {
                    Text("Show \(store.hiddenCount) hidden tasks")
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .surface(in: Capsule())
                }
                .buttonStyle(PressableRowStyle())
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 2)
        .padding(.bottom, 22)
    }
}

/// The app's orbit drawn large and quiet, for the empty state.
struct OrbitMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 18
            let center = CGPoint(x: 9 * scale, y: 9 * scale)
            let ring = Path(ellipseIn: CGRect(x: center.x - 6 * scale, y: center.y - 6 * scale, width: 12 * scale, height: 12 * scale))
            context.stroke(ring, with: .style(.tertiary), style: StrokeStyle(lineWidth: 0.9 * scale, lineCap: .round, dash: [1.2 * scale, 1.6 * scale]))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1.2 * scale, y: center.y - 1.2 * scale, width: 2.4 * scale, height: 2.4 * scale)), with: .style(.secondary))
            let bead = CGRect(x: 13.24 * scale - 1.9 * scale, y: 4.76 * scale - 1.9 * scale, width: 3.8 * scale, height: 3.8 * scale)
            context.fill(Path(ellipseIn: bead), with: .color(.white))
            context.stroke(Path(ellipseIn: bead), with: .style(.tertiary), lineWidth: 0.7 * scale / 2)
        }
    }
}
