import SwiftUI
import NewtonCore
import NewtonWorkspace

public struct TimeMachineScrubberView: View {
    @Bindable var model: WorkspaceModel
    @State private var selectedIndex = 0.0
    @Environment(\.colorScheme) private var colorScheme

    public init(model: WorkspaceModel) {
        self.model = model
    }

    private var frame: TimeMachineFrame? {
        guard !model.timeline.isEmpty else { return nil }
        return model.timeline[min(Int(selectedIndex), model.timeline.count - 1)]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label("Daily Observations & Time Machine", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                DatePicker("", selection: $model.timelineDate, displayedComponents: .date)
                    .labelsHidden()
                    .controlSize(.small)
            }

            if model.timelineBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Synthesizing daily history…").font(.caption).foregroundStyle(.secondary)
                }
            }

            if let error = model.timelineError {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Retry", action: model.requestTimeline)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            if !model.timelineComplete {
                Text("Incomplete: first 50,000 events shown")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("\(model.timelineSummary.observationCount) records · \(model.timelineSummary.observedIntervals) observed 5-min intervals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if !model.timeline.isEmpty {
                VStack(spacing: 6) {
                    HStack(spacing: 1.5) {
                        ForEach(Array(model.timeline.enumerated()), id: \.element.id) { idx, frame in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(frame.hasObservations ? Color.accentColor : Color.white.opacity(colorScheme == .light ? 0.15 : 0.08))
                                .frame(height: 16)
                                .onTapGesture {
                                    selectedIndex = Double(idx)
                                }
                        }
                    }
                    .accessibilityLabel("Observed intervals")

                    Slider(value: $selectedIndex, in: 0...Double(max(1, model.timeline.count - 1)), step: 1)
                        .controlSize(.small)
                        .accessibilityLabel("Five-minute interval")
                }
            }

            if let frame {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(frame.timeString)
                            .font(.system(.subheadline, design: .monospaced).bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        Spacer()
                        if !frame.hasObservations {
                            Text("No observations in this 5m window")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !frame.observations.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(frame.observations) { event in
                                    HStack(alignment: .top, spacing: 6) {
                                        Circle()
                                            .fill(Color.accentColor.opacity(0.7))
                                            .frame(width: 5, height: 5)
                                            .padding(.top, 5)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(event.source) · \(event.title)").font(.caption.bold())
                                            if !event.detail.isEmpty {
                                                Text(event.detail)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                }
                                ForEach(frame.commitMarkers, id: \.self) { commit in
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.branch").font(.caption2).foregroundStyle(.orange)
                                        Text(commit).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                    }
                }
                .padding(10)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .panelCard(cornerRadius: 14)
        .onAppear { model.presentTimeline() }
        .onDisappear { model.dismissTimeline() }
    }
}
