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

    private var header: some View {
        HStack(alignment: .center) {
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
        case .failed: return store.failedCount == 1 ? "1 job failed" : "\(store.failedCount) jobs failed"
        case .headsUp: return store.overlapCount == 1 ? "1 job needs a look" : "\(store.overlapCount) jobs need a look"
        case .running: return store.activeRunCount == 1 ? "1 job running" : "\(store.activeRunCount) jobs running"
        case .ok: return "All good"
        }
    }

    private var subtitle: Text {
        let count = store.activeCount
        guard count > 0 else { return Text(store.jobs.isEmpty ? "Looking for jobs…" : "Nothing to watch") }
        return Text(count == 1 ? "Watching 1 job" : "Watching \(count) jobs")
    }

    @ViewBuilder
    private func list(_ jobs: [Job]) -> some View {
        let rows = VStack(spacing: 0) {
            ForEach(jobs) { job in
                JobRowView(store: store, job: job, now: now) { onSelect(job) }
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

    var body: some View {
        Menu {
            Toggle(isOn: $store.showHidden) {
                Label("Show Hidden Jobs (\(store.hiddenCount))", systemImage: "eye.slash")
            }
            Toggle(isOn: Binding(get: { store.launchesAtLogin }, set: { store.launchesAtLogin = $0 })) {
                Label("Open at Login", systemImage: "power")
            }
            Divider()
            Button {
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(nil)
            } label: {
                Label("About onit", systemImage: "info.circle")
            }
            Divider()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit onit", systemImage: "xmark.circle")
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(GlassCircleButtonStyle())
        .fixedSize()
        .help("More")
    }
}

/// Spins exactly one turn per refresh, around the glyph's own center, however fast the refresh is.
struct RefreshButton: View {
    let store: JobStore
    @State private var turns = 0.0

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.6)) { turns += 1 }
            Task { await store.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(turns * 360), anchor: .center)
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
                Button("Show \(store.hiddenCount) hidden jobs") { store.showHidden = true }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
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
