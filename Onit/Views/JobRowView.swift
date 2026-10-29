import SwiftUI

struct JobRowView: View {
    let store: JobStore
    let job: Job
    let now: Date
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                StatusDot(job: job)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(job.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(job.state == .paused || job.isHidden ? .secondary : .primary)
                            .lineLimit(1)
                        SourceTag(source: job.source)
                        if job.isHidden {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    HStack(spacing: 5) {
                        if job.schedule.hasOverlap {
                            BeadGlyph(mood: .headsUp, size: 11)
                        }
                        Text(ScheduleText.summary(job.schedule))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    let style = StatusStyle(job)
                    Text(style.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(style.color)
                    if let detail = statusDetail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                .monospacedDigit()
                .frame(width: Metrics.statusColumn, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowFill)
            )
        }
        .buttonStyle(PressableRowStyle(pressedScale: 0.98))
        .contextMenu {
            Button(job.isHidden ? "Show in List" : "Hide from List") {
                store.setHidden(job, hidden: !job.isHidden)
            }
        }
    }

    /// Hover is drawn by the list's shared highlight; a failed row keeps a faint red wash underneath it.
    private var rowFill: Color {
        if case .failed = job.state { return Color.red.opacity(0.08) }
        return .clear
    }

    private var statusDetail: String? {
        switch job.state {
        case .running:
            return store.runningSince(job).map { TimeText.elapsed(since: $0, now: now) }
        case .paused:
            return nil
        case .waiting:
            return store.nextRun(for: job, now: now).map { TimeText.until($0, now: now) }
        case .succeeded, .failed:
            return job.lastRun.map { TimeText.ago($0, now: now) }
        }
    }
}
