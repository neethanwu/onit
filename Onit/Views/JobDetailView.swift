import SwiftUI

struct JobDetailView: View {
    let store: JobStore
    let job: Job
    let now: Date
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            banner
                .padding(.horizontal, 6)
            facts
            if !job.isAlwaysOn {
                RecentRunsSection(store: store, job: job, now: now)
            }
            ActionBar(store: store, job: job)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(GlassCircleButtonStyle())
            .help("All tasks")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(job.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    SourceTag(source: job.source)
                }
                HStack(spacing: 6) {
                    StatusDot(job: job)
                        .scaleEffect(0.85)
                        .frame(width: 8)
                    statusLine
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, Metrics.edge)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var statusLine: Text {
        let next = store.nextRun(for: job, now: now)
        let nextText = next.map { "next \(TimeText.until($0, now: now))" }
        switch job.state {
        case .failed:
            let when = job.lastRun.map { " \(TimeText.ago($0, now: now))" } ?? ""
            return joined(Text("Failed\(when)").foregroundStyle(.red).fontWeight(.medium), nextText)
        case .succeeded:
            return joined(Text("Last run OK").foregroundStyle(.green).fontWeight(.medium), nextText)
        case .running:
            let since = store.runningSince(job).map { " \(TimeText.elapsed(since: $0, now: now))" } ?? ""
            return Text("Running\(since)").foregroundStyle(.blue).fontWeight(.medium)
        case .paused:
            return Text("Paused · won't run until you resume it")
        case .waiting:
            if job.source == .cron {
                let ran = job.lastRun.map { "Ran \(TimeText.ago($0, now: now))" } ?? "Scheduled"
                return joined(Text(ran), nextText)
            }
            return joined(Text("Hasn't run yet"), next.map { "first run \(TimeText.until($0, now: now))" })
        }
    }

    private func joined(_ lead: Text, _ tail: String?) -> Text {
        guard let tail else { return lead }
        return Text("\(lead) · \(tail)")
    }

    @ViewBuilder
    private var banner: some View {
        if case .failed = job.state {
            ProblemCard(store: store, job: job)
        } else if job.schedule.hasOverlap {
            OverlapCard(store: store, job: job)
        }
    }

    private var facts: some View {
        let next = store.nextRun(for: job, now: now)
        return VStack(spacing: 0) {
            FactRow(label: "Schedule") {
                Text(ScheduleText.summary(job.schedule)).lineLimit(1)
            }
            if let next {
                FactRow(label: "Next run") {
                    Text(TimeText.dayAndTime(next, now: now)).monospacedDigit()
                }
            }
            FactRow(label: "What it runs", showsDivider: false) {
                Label(JobNaming.whatItRuns(job), systemImage: "folder")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
            .help(job.commandLine)
        }
        .padding(.horizontal, Metrics.edge)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

// MARK: - Banners

struct ProblemCard: View {
    let store: JobStore
    let job: Job

    var body: some View {
        let tail = job.logPath.map { FailureExplainer.readTail(ofFile: $0) } ?? ""
        let explanation = FailureExplainer.explain(exitCode: job.lastExitCode, logTail: tail)
        let streak = store.failureStreak(for: job)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                BeadGlyph(mood: .failed, size: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(streak > 1 ? "Didn't finish \(streak) times in a row" : "Didn't finish last time")
                        .font(.system(size: 12, weight: .semibold))
                    Text(reason(explanation))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    if let raw = explanation.rawLine {
                        Text(raw)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                            .padding(.top, 2)
                    }
                }
            }
            HStack(spacing: 10) {
                CopyButton(title: "Copy for your agent", tint: .red, text: {
                    FixPrompt.forFailure(job, explanation: explanation, logTail: tail)
                }, store: store)
                Text("With the error and log")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 26)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func reason(_ explanation: FailureExplainer.Explanation) -> String {
        guard let success = store.lastSuccess(for: job) else { return explanation.reason }
        return explanation.reason + " It worked until \(TimeText.shortDay(success))."
    }
}

struct OverlapCard: View {
    let store: JobStore
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                BeadGlyph(mood: .headsUp, size: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runs more often than you might think")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(ScheduleText.summary(job.schedule)). That's about \(ScheduleText.runsPerDay(job.schedule)) runs a day.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                CopyButton(title: "Copy fix prompt", tint: .orange, text: { FixPrompt.forOverlap(job) }, store: store)
                Text("Paste it to your agent")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 26)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Recent runs

struct RecentRunsSection: View {
    let store: JobStore
    let job: Job
    let now: Date

    var body: some View {
        let records = Array(store.records(for: job).suffix(5).reversed())
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent runs").font(.system(size: 12, weight: .medium))
                Spacer()
                if job.logPath != nil {
                    Button("See full log") { store.openLog(job) }
                        .buttonStyle(.link)
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
            if records.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        RunRow(record: record, now: now, showsDivider: index < records.count - 1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .card()
            }
        }
        .padding(.horizontal, Metrics.edge)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No runs recorded yet")
                .font(.system(size: 12, weight: .medium))
            Text(emptyMessage)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    private var emptyMessage: String {
        if job.source == .cron, job.logPath == nil {
            return "cron doesn't report its runs. Send the command's output to a log file and onit will pick them up."
        }
        return "onit keeps track from the moment it's installed. Each run will show up here."
    }
}

struct RunRow: View {
    let record: RunRecord
    let now: Date
    let showsDivider: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(TimeText.runDay(record.end ?? record.start, now: now))
                .font(.system(size: 12))
                .monospacedDigit()
            Spacer()
            Text(outcome)
                .font(.system(size: 11.5))
                .foregroundStyle(failed ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tertiary))
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if showsDivider { Divider().opacity(0.5) }
        }
    }

    private var failed: Bool {
        if let code = record.exitCode { return code != 0 }
        return false
    }

    private var color: Color {
        if record.end == nil { return .blue }
        if record.exitCode == nil { return .secondary }
        return failed ? .red : .green
    }

    private var outcome: String {
        guard record.end != nil else { return "Running…" }
        let duration = record.duration.map(TimeText.duration)
        if failed { return duration.map { "Stopped after \($0)" } ?? "Didn't finish" }
        if record.exitCode == nil { return "Ran" }
        return duration.map { "Finished in \($0)" } ?? "Finished"
    }
}

// MARK: - Actions

struct ActionBar: View {
    let store: JobStore
    let job: Job
    @State private var phase = RunPhase.idle

    enum RunPhase {
        case idle, starting, started
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                run()
            } label: {
                runLabel
            }
            .buttonStyle(GlassCapsuleButtonStyle(prominent: true))
            .disabled(phase != .idle || job.state == .running)

            if job.source == .launchd {
                Button {
                    Task { await store.setPaused(job, paused: job.state != .paused) }
                } label: {
                    Label(job.state == .paused ? "Resume" : "Pause", systemImage: job.state == .paused ? "play" : "pause.fill")
                }
                .buttonStyle(GlassCapsuleButtonStyle())
            }

            MoreButton(id: "task", size: Metrics.actionHeight, opensUpward: true) { entries }
        }
        .labelStyle(CompactLabelStyle())
        .padding(.horizontal, Metrics.edge)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    private var entries: [MenuEntry] {
        var entries: [MenuEntry] = []
        if job.plistURL != nil {
            entries.append(.item(title: "Show in Finder", systemImage: "folder") { store.revealDefinition(job) })
        }
        if job.logPath != nil {
            entries.append(.item(title: "Open Log", systemImage: "doc.text") { store.openLog(job) })
        }
        entries.append(.item(title: "Copy Command", systemImage: "doc.on.doc") { store.copy(job.commandLine) })
        entries.append(.divider(id: "hide"))
        entries.append(.item(title: job.isHidden ? "Show in List" : "Hide from List", systemImage: job.isHidden ? "eye" : "eye.slash") {
            store.setHidden(job, hidden: !job.isHidden)
        })
        return entries
    }

    @ViewBuilder
    private var runLabel: some View {
        switch phase {
        case .idle:
            Label(isFailed ? "Try Again" : "Run Now", systemImage: "play.fill")
        case .starting:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Starting…")
            }
        case .started:
            Label("Started", systemImage: "checkmark")
        }
    }

    private var isFailed: Bool {
        if case .failed = job.state { return true }
        return false
    }

    private func run() {
        withAnimation(.easeOut(duration: 0.2)) { phase = .starting }
        Task {
            await store.runNow(job)
            withAnimation(.easeOut(duration: 0.2)) { phase = .started }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.2)) { phase = .idle }
        }
    }
}
