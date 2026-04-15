import AppKit
import AutoTapCore
import SwiftUI

private enum ContentLayoutMode {
    case regular
    case compact
}

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var layoutMode: ContentLayoutMode = .regular

    private let compactWidth: CGFloat = 620

    private var editorLocked: Bool {
        viewModel.isAnyRunning || viewModel.hasActiveCountdown || viewModel.isPickingFromScreen
    }

    private var shouldAutoPresentMiniBar: Bool {
        viewModel.hasActiveCountdown || viewModel.isAnyRunning
    }

    private var currentSourceWindow: NSWindow? {
        MainWindowRegistry.shared.window ?? NSApp.keyWindow ?? NSApp.mainWindow
    }

    var body: some View {
        let strings = viewModel.strings

        Group {
            if layoutMode == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .frame(minWidth: 420, minHeight: 340)
        .background(WindowBehaviorBridge(layoutMode: $layoutMode, compactWidth: compactWidth))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        viewModel.addSinglePointUnit()
                    } label: {
                        ActionLabel(title: strings.addSinglePoint, systemImage: "plus.viewfinder")
                    }
                    .disabled(editorLocked)

                    Button {
                        viewModel.addPointGroupUnit()
                    } label: {
                        ActionLabel(title: strings.addPointGroup, systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .disabled(editorLocked)
                } label: {
                    ActionLabel(title: strings.add, systemImage: "plus.circle")
                }

                Button {
                    MiniBarWindowController.shared.toggle(viewModel: viewModel, sourceWindow: currentSourceWindow)
                } label: {
                    ActionLabel(title: strings.showMiniBar, systemImage: "rectangle.compress.vertical")
                }

                Button {
                    SettingsWindowController.shared.show(viewModel: viewModel)
                } label: {
                    ActionLabel(title: strings.openSettings, systemImage: "gearshape")
                }

                Button {
                    viewModel.startAll()
                } label: {
                    ActionLabel(title: strings.startAll, systemImage: "play.fill")
                }
                .disabled(viewModel.units.allSatisfy { $0.isRunning } || !viewModel.canStartClicks)

                Button {
                    viewModel.stopAll()
                } label: {
                    ActionLabel(title: strings.stopAll, systemImage: "stop.fill")
                }
                .disabled(!viewModel.isAnyRunning && !viewModel.hasActiveCountdown && !viewModel.isPickingFromScreen)
            }
        }
        .onAppear {
            viewModel.refreshAccessibilityStatus()
        }
        .onChange(of: shouldAutoPresentMiniBar) { shouldAutoPresentMiniBar in
            guard shouldAutoPresentMiniBar, !MiniBarWindowController.shared.isVisible else {
                return
            }

            MiniBarWindowController.shared.show(viewModel: viewModel, sourceWindow: currentSourceWindow)
        }
        .overlay {
            if let countdownState = viewModel.countdownState {
                CountdownOverlayView(state: countdownState, strings: strings)
            }
        }
        .alert(
            strings.persistenceError,
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { presented in
                    if !presented {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button(strings.dismiss, role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane(horizontalPadding: 24)
        }
        .navigationSplitViewStyle(.prominentDetail)
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SafetyPanelView(viewModel: viewModel)
                CompactUnitBrowserView(viewModel: viewModel, editorLocked: editorLocked)
                unitEditorSection
                HistoryPanelView(viewModel: viewModel)
            }
            .padding(18)
        }
    }

    private var sidebar: some View {
        let strings = viewModel.strings

        return VStack(alignment: .leading, spacing: 12) {
            Text(strings.configuredUnits)
                .font(.title3.weight(.semibold))

            Text(strings.configuredUnitsDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)

            List(selection: $viewModel.selectedUnitID) {
                ForEach(viewModel.units) { unit in
                    UnitRowView(
                        unit: unit,
                        runProgress: viewModel.runProgress(for: unit.id),
                        canDelete: !editorLocked,
                        strings: strings,
                        onDelete: {
                            viewModel.removeUnit(id: unit.id)
                        }
                    )
                    .tag(unit.id)
                }
            }
            .listStyle(.sidebar)
        }
        .padding()
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
    }

    private func detailPane(horizontalPadding: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SafetyPanelView(viewModel: viewModel)
                unitEditorSection
                HistoryPanelView(viewModel: viewModel)
            }
            .padding(horizontalPadding)
        }
    }

    @ViewBuilder
    private var unitEditorSection: some View {
        if let selectedUnitIndex = viewModel.selectedUnitIndex {
            UnitEditorView(unit: $viewModel.units[selectedUnitIndex], viewModel: viewModel)
        } else {
            let strings = viewModel.strings

            VStack(alignment: .leading, spacing: 14) {
                Text(strings.noUnitSelected)
                    .font(.largeTitle.weight(.semibold))

                Text(strings.noUnitSelectedDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        viewModel.addSinglePointUnit()
                    } label: {
                        ActionLabel(title: strings.addSinglePoint, systemImage: "plus.viewfinder")
                    }
                    .disabled(editorLocked)

                    Button {
                        viewModel.addPointGroupUnit()
                    } label: {
                        ActionLabel(title: strings.addPointGroup, systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .disabled(editorLocked)
                }
            }
        }
    }
}

private struct ActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
    }
}

private struct CompactUnitBrowserView: View {
    @ObservedObject var viewModel: AppViewModel
    let editorLocked: Bool

    var body: some View {
        let strings = viewModel.strings

        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(strings.compactLayoutDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(viewModel.units) { unit in
                        Button {
                            viewModel.selectedUnitID = unit.id
                        } label: {
                            Label(
                                unit.name,
                                systemImage: unit.id == viewModel.selectedUnitID ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(strings.selectUnit)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            Text(viewModel.selectedUnit?.name ?? strings.noUnitSelected)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let selectedUnit = viewModel.selectedUnit {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(strings.kindDisplayName(selectedUnit.kind))
                            .font(.subheadline.weight(.medium))

                        Text(strings.unitSummary(selectedUnit))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(strings.frequencySummary(selectedUnit.frequencyHz) + " • " + strings.runDurationSummary(selectedUnit.runDurationSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(strings.noUnitSelectedDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        viewModel.addSinglePointUnit()
                    } label: {
                        ActionLabel(title: strings.addSinglePoint, systemImage: "plus.viewfinder")
                    }
                    .disabled(editorLocked)

                    Button {
                        viewModel.addPointGroupUnit()
                    } label: {
                        ActionLabel(title: strings.addPointGroup, systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .disabled(editorLocked)
                }
            }
        } label: {
            Label(strings.configuredUnits, systemImage: "rectangle.stack")
        }
    }
}

private struct SafetyPanelView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        let strings = viewModel.strings

        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    viewModel.isAccessibilityTrusted ? strings.accessibilityActive : strings.accessibilityRequired,
                    systemImage: viewModel.isAccessibilityTrusted ? "checkmark.shield" : "hand.raised.fill"
                )
                .foregroundStyle(viewModel.isAccessibilityTrusted ? Color.green : Color.orange)

                Label(
                    viewModel.emergencyStopSummary,
                    systemImage: viewModel.isEmergencyStopArmed ? "escape" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(viewModel.isEmergencyStopArmed ? Color.primary : Color.red)

                if let prompt = viewModel.screenPickPrompt {
                    Label(prompt, systemImage: "scope")
                        .foregroundStyle(.blue)
                }

                if let preview = viewModel.screenPickPreview {
                    Label(strings.liveCoordinates(preview.coordinatesSummary), systemImage: "location.viewfinder")
                        .foregroundStyle(.blue)
                }

                if let countdownState = viewModel.countdownState {
                    Label(strings.countdownActive(countdownState.secondsRemaining), systemImage: "timer")
                        .foregroundStyle(.blue)
                }

                if viewModel.isAnyRunning {
                    Label(strings.clickingActiveNow, systemImage: "bolt.fill")
                        .foregroundStyle(.red)
                }

                HStack(spacing: 10) {
                    if !viewModel.isAccessibilityTrusted {
                        Button {
                            viewModel.requestAccessibilityPermission()
                        } label: {
                            ActionLabel(title: strings.promptAccessibility, systemImage: "hand.raised")
                        }
                    }

                    Button {
                        viewModel.refreshAccessibilityStatus()
                    } label: {
                        ActionLabel(title: strings.refreshStatus, systemImage: "arrow.clockwise")
                    }

                    if viewModel.isPickingFromScreen {
                        Button {
                            viewModel.cancelCurrentScreenPick()
                        } label: {
                            ActionLabel(title: strings.cancelPick, systemImage: "xmark.circle")
                        }
                    }

                    if viewModel.hasActiveCountdown {
                        Button {
                            viewModel.stopAll()
                        } label: {
                            ActionLabel(title: strings.cancelCountdown, systemImage: "timer.circle")
                        }
                    }
                }
            }
        } label: {
            Label(strings.safetyControls, systemImage: "exclamationmark.shield")
        }
    }
}

private struct UnitRowView: View {
    let unit: ClickUnit
    let runProgress: AppViewModel.RunProgress?
    let canDelete: Bool
    let strings: AppStrings
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(unit.isRunning ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(unit.name)
                        .font(.headline)

                    KindTag(kind: unit.kind, strings: strings)
                }

                Text(strings.unitSummary(unit))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(strings.frequencySummary(unit.frequencyHz) + " • " + (runProgress.map { strings.runProgressSummary($0.remainingSeconds) } ?? strings.runDurationSummary(unit.runDurationSeconds)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!canDelete)
        }
        .padding(.vertical, 4)
    }
}

private struct UnitEditorView: View {
    @Binding var unit: ClickUnit
    @ObservedObject var viewModel: AppViewModel

    private var configurationLocked: Bool {
        viewModel.isAnyRunning || viewModel.hasActiveCountdown || viewModel.isPickingFromScreen
    }

    var body: some View {
        let strings = viewModel.strings

        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(unit.name)
                                .font(.title2.weight(.semibold))

                            Text(strings.kindDisplayName(unit.kind))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            viewModel.toggleRunning(unit.id)
                        } label: {
                            ActionLabel(
                                title: unit.isRunning ? strings.stopUnit : strings.startUnit,
                                systemImage: unit.isRunning ? "stop.fill" : "play.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!unit.isRunning && !viewModel.canStartClicks)
                    }

                    BufferedTextField(
                        title: strings.unitName,
                        text: $unit.name,
                        isDisabled: configurationLocked
                    )

                    HStack {
                        Text(strings.frequency)
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        BufferedDoubleField(
                            title: strings.frequency,
                            value: $unit.frequencyHz,
                            width: 90,
                            maximumFractionDigits: 2,
                            isDisabled: configurationLocked
                        )

                        Stepper("", value: $unit.frequencyHz, in: 0.1 ... 200, step: 0.1)
                            .labelsHidden()
                            .disabled(configurationLocked)
                    }

                    HStack {
                        Text(strings.autoStop)
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        BufferedDoubleField(
                            title: strings.seconds,
                            value: $unit.runDurationSeconds,
                            width: 90,
                            maximumFractionDigits: 0,
                            isDisabled: configurationLocked
                        )

                        Stepper("", value: $unit.runDurationSeconds, in: 0 ... 86_400, step: 1)
                            .labelsHidden()
                            .disabled(configurationLocked)
                    }

                    Text(strings.autoStopHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let runProgress = viewModel.runProgress(for: unit.id) {
                        Label(strings.timerActive(strings.runProgressSummary(runProgress.remainingSeconds)), systemImage: "timer")
                            .foregroundStyle(.blue)
                    }

                    HStack(spacing: 10) {
                        Button {
                            viewModel.duplicateSelectedUnit()
                        } label: {
                            ActionLabel(title: strings.duplicateUnit, systemImage: "plus.square.on.square")
                        }
                        .disabled(configurationLocked)

                        Spacer()

                        Button(role: .destructive) {
                            viewModel.removeUnit(id: unit.id)
                        } label: {
                            ActionLabel(title: strings.removeUnit, systemImage: "trash")
                        }
                        .disabled(configurationLocked)
                    }
                }
            } label: {
                Label(strings.unitSettings, systemImage: "slider.horizontal.3")
            }

            if unit.kind == .singlePoint {
                SinglePointEditorView(unit: $unit, viewModel: viewModel)
            } else {
                PointGroupEditorView(unit: $unit, viewModel: viewModel)
            }
        }
    }
}

private struct SinglePointEditorView: View {
    @Binding var unit: ClickUnit
    @ObservedObject var viewModel: AppViewModel

    private var isPicking: Bool {
        viewModel.isPickingSinglePoint(unitID: unit.id)
    }

    private var configurationLocked: Bool {
        viewModel.isAnyRunning || viewModel.hasActiveCountdown || (viewModel.isPickingFromScreen && !isPicking)
    }

    var body: some View {
        let strings = viewModel.strings

        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                CoordinateEditorView(point: $unit.singlePoint, isDisabled: configurationLocked, strings: strings)

                HStack {
                    Button {
                        if isPicking {
                            viewModel.cancelCurrentScreenPick()
                        } else {
                            viewModel.beginSinglePointPick(unitID: unit.id)
                        }
                    } label: {
                        ActionLabel(
                            title: isPicking ? strings.cancelPick : strings.pickFromScreen,
                            systemImage: isPicking ? "xmark.circle" : "scope"
                        )
                    }
                    .disabled(viewModel.isAnyRunning || viewModel.hasActiveCountdown || (viewModel.isPickingFromScreen && !isPicking))

                    Spacer()

                    Text(strings.coordinatesSummary(unit.singlePoint))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label(strings.clickPosition, systemImage: "scope")
        }
    }
}

private struct PointGroupEditorView: View {
    @Binding var unit: ClickUnit
    @ObservedObject var viewModel: AppViewModel

    private var configurationLocked: Bool {
        viewModel.isAnyRunning || viewModel.hasActiveCountdown || viewModel.isPickingFromScreen
    }

    var body: some View {
        let strings = viewModel.strings

        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text(strings.pointGroupDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(Array(unit.groupPoints.indices), id: \.self) { index in
                    GroupPointRowView(
                        point: $unit.groupPoints[index],
                        unitID: unit.id,
                        canMoveUp: index > 0,
                        canMoveDown: index < unit.groupPoints.count - 1,
                        canDelete: unit.groupPoints.count > 1,
                        viewModel: viewModel
                    )
                }

                HStack {
                    Button {
                        viewModel.addGroupPoint(to: unit.id)
                    } label: {
                        ActionLabel(title: strings.addPoint, systemImage: "plus.circle")
                    }
                    .disabled(configurationLocked)

                    Spacer()

                    Text(strings.pointsInSequence(unit.groupPoints.count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label(strings.pointGroup, systemImage: "point.3.connected.trianglepath.dotted")
        }
    }
}

private struct GroupPointRowView: View {
    @Binding var point: ScreenPoint
    let unitID: UUID
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool
    @ObservedObject var viewModel: AppViewModel

    private var isPicking: Bool {
        viewModel.isPickingGroupPoint(unitID: unitID, pointID: point.id)
    }

    private var configurationLocked: Bool {
        viewModel.isAnyRunning || viewModel.hasActiveCountdown || (viewModel.isPickingFromScreen && !isPicking)
    }

    var body: some View {
        let strings = viewModel.strings

        VStack(alignment: .leading, spacing: 10) {
            CoordinateEditorView(point: $point, isDisabled: configurationLocked, strings: strings)

            HStack(spacing: 10) {
                Button {
                    if isPicking {
                        viewModel.cancelCurrentScreenPick()
                    } else {
                        viewModel.beginGroupPointPick(unitID: unitID, pointID: point.id)
                    }
                } label: {
                    ActionLabel(
                        title: isPicking ? strings.cancelPick : strings.pickFromScreen,
                        systemImage: isPicking ? "xmark.circle" : "scope"
                    )
                }
                .disabled(viewModel.isAnyRunning || viewModel.hasActiveCountdown || (viewModel.isPickingFromScreen && !isPicking))

                Button {
                    viewModel.moveGroupPoint(unitID: unitID, pointID: point.id, direction: -1)
                } label: {
                    ActionLabel(title: strings.moveUp, systemImage: "arrow.up")
                }
                .disabled(!canMoveUp || configurationLocked)

                Button {
                    viewModel.moveGroupPoint(unitID: unitID, pointID: point.id, direction: 1)
                } label: {
                    ActionLabel(title: strings.moveDown, systemImage: "arrow.down")
                }
                .disabled(!canMoveDown || configurationLocked)

                Spacer()

                Button(role: .destructive) {
                    viewModel.removeGroupPoint(unitID: unitID, pointID: point.id)
                } label: {
                    ActionLabel(title: strings.removePoint, systemImage: "minus.circle")
                }
                .disabled(!canDelete || configurationLocked)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CoordinateEditorView: View {
    @Binding var point: ScreenPoint
    var isDisabled: Bool
    let strings: AppStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BufferedTextField(
                title: strings.pointName,
                text: $point.name,
                isDisabled: isDisabled
            )

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(strings.xAxis)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    BufferedDoubleField(
                        title: strings.xAxis,
                        value: $point.x,
                        width: 110,
                        maximumFractionDigits: 2,
                        isDisabled: isDisabled
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(strings.yAxis)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    BufferedDoubleField(
                        title: strings.yAxis,
                        value: $point.y,
                        width: 110,
                        maximumFractionDigits: 2,
                        isDisabled: isDisabled
                    )
                }

                Spacer()
            }
        }
    }
}

private struct BufferedTextField: View {
    let title: String
    @Binding var text: String
    var width: CGFloat? = nil
    var isDisabled: Bool = false

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .focused($isFocused)
            .disabled(isDisabled)
            .onAppear {
                draft = text
            }
            .onChange(of: text) { newValue in
                if !isFocused && draft != newValue {
                    draft = newValue
                }
            }
            .onChange(of: isFocused) { focused in
                if !focused {
                    commit()
                }
            }
            .onSubmit {
                commit()
            }
    }

    private func commit() {
        if text != draft {
            text = draft
        } else if draft != text {
            draft = text
        }
    }
}

struct BufferedIntField: View {
    let title: String
    @Binding var value: Int
    var width: CGFloat? = nil
    var isDisabled: Bool = false

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .focused($isFocused)
            .disabled(isDisabled)
            .onAppear {
                draft = String(value)
            }
            .onChange(of: value) { newValue in
                let formatted = String(newValue)
                if !isFocused && draft != formatted {
                    draft = formatted
                }
            }
            .onChange(of: isFocused) { focused in
                if !focused {
                    commit()
                }
            }
            .onSubmit {
                commit()
            }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = Int(trimmed) else {
            draft = String(value)
            return
        }

        if value != parsed {
            value = parsed
        }
        draft = String(value)
    }
}

private struct BufferedDoubleField: View {
    let title: String
    @Binding var value: Double
    var width: CGFloat? = nil
    var maximumFractionDigits: Int
    var isDisabled: Bool = false

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .focused($isFocused)
            .disabled(isDisabled)
            .onAppear {
                draft = formattedValue(value)
            }
            .onChange(of: value) { newValue in
                let formatted = formattedValue(newValue)
                if !isFocused && draft != formatted {
                    draft = formatted
                }
            }
            .onChange(of: isFocused) { focused in
                if !focused {
                    commit()
                }
            }
            .onSubmit {
                commit()
            }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draft = formattedValue(value)
            return
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized) else {
            draft = formattedValue(value)
            return
        }

        if value != parsed {
            value = parsed
        }
        draft = formattedValue(value)
    }

    private func formattedValue(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

private struct WindowBehaviorBridge: NSViewRepresentable {
    @Binding var layoutMode: ContentLayoutMode
    let compactWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(layoutMode: $layoutMode, compactWidth: compactWidth)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.layoutMode = $layoutMode
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
        }
    }

    final class Coordinator {
        var layoutMode: Binding<ContentLayoutMode>
        private let compactWidth: CGFloat
        private weak var window: NSWindow?
        private var lastStableFrame: NSRect?
        private var observers: [NSObjectProtocol] = []

        init(layoutMode: Binding<ContentLayoutMode>, compactWidth: CGFloat) {
            self.layoutMode = layoutMode
            self.compactWidth = compactWidth
        }

        deinit {
            tearDownObservers()
        }

        func attach(to window: NSWindow?) {
            guard let window else {
                return
            }
            guard self.window !== window else {
                return
            }

            tearDownObservers()
            self.window = window
            configure(window)
            lastStableFrame = window.frame
            updateLayoutMode(for: window.frame.width, force: true)
            registerObservers(for: window)

            DispatchQueue.main.async {
                self.restoreIfNeeded(forceKey: true)
            }
        }

        private func configure(_ window: NSWindow) {
            window.hidesOnDeactivate = false
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.isReleasedWhenClosed = false
            window.level = .normal
            window.identifier = autoTapMainWindowIdentifier
            MainWindowRegistry.shared.window = window
        }

        private func registerObservers(for window: NSWindow) {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                    self?.captureFrame()
                },
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    self?.captureFrame()
                    self?.updateLayoutIfNeededAfterResize(liveResizeEnded: false)
                },
                center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak self] _ in
                    self?.captureFrame()
                    self?.updateLayoutIfNeededAfterResize(liveResizeEnded: true)
                },
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    self?.restoreIfNeeded(forceKey: false)
                },
                center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
                    self?.restoreIfNeeded(forceKey: true)
                },
            ]
        }

        private func tearDownObservers() {
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers.removeAll()
        }

        private func captureFrame() {
            guard let window, window.isVisible, !window.isMiniaturized else {
                return
            }
            guard NSApp.isActive || window.isKeyWindow else {
                return
            }

            lastStableFrame = window.frame
        }

        private func updateLayoutIfNeededAfterResize(liveResizeEnded: Bool) {
            guard let window else {
                return
            }

            if liveResizeEnded || !window.inLiveResize {
                updateLayoutMode(for: window.frame.width, force: true)
            }
        }

        private func updateLayoutMode(for width: CGFloat, force: Bool) {
            let nextMode: ContentLayoutMode = width < compactWidth ? .compact : .regular
            if force && layoutMode.wrappedValue != nextMode {
                layoutMode.wrappedValue = nextMode
            }
        }

        private func restoreIfNeeded(forceKey: Bool) {
            guard let window, window.isVisible else {
                return
            }

            configure(window)

            let miniBarIsVisible = NSApp.windows.contains { candidate in
                candidate.identifier == autoTapMiniBarWindowIdentifier && candidate.isVisible
            }
            if miniBarIsVisible {
                return
            }

            if forceKey {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }

            guard let lastStableFrame else {
                return
            }

            let origin = window.frame.origin
            let deltaX = abs(origin.x - lastStableFrame.origin.x)
            let deltaY = abs(origin.y - lastStableFrame.origin.y)
            if deltaX > 2 || deltaY > 2 {
                window.setFrame(lastStableFrame, display: true)
            }
        }
    }
}

private struct HistoryPanelView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var historyPage = 0

    private let pageSize = 6

    private var restoreDisabled: Bool {
        viewModel.isAnyRunning || viewModel.hasActiveCountdown || viewModel.isPickingFromScreen
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(viewModel.filteredHistory.count) / Double(pageSize))))
    }

    private var currentPage: Int {
        min(historyPage, totalPages - 1)
    }

    private var pagedHistory: ArraySlice<HistoryRecord> {
        let startIndex = currentPage * pageSize
        let endIndex = min(startIndex + pageSize, viewModel.filteredHistory.count)
        return viewModel.filteredHistory[startIndex..<endIndex]
    }

    var body: some View {
        let strings = viewModel.strings

        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text(strings.historyDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if viewModel.filteredHistory.isEmpty {
                    Text(viewModel.autoSaveExecutedUnitsToHistory ? strings.noHistoryYet : strings.autoSaveOffHistoryHint)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(strings.historyPage(currentPage + 1, totalPages))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            historyPage = max(0, currentPage - 1)
                        } label: {
                            ActionLabel(title: strings.previousPage, systemImage: "chevron.left")
                        }
                        .disabled(currentPage == 0)

                        Button {
                            historyPage = min(totalPages - 1, currentPage + 1)
                        } label: {
                            ActionLabel(title: strings.nextPage, systemImage: "chevron.right")
                        }
                        .disabled(currentPage >= totalPages - 1)
                    }

                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(pagedHistory)) { record in
                            HistoryRowView(record: record, viewModel: viewModel, restoreDisabled: restoreDisabled)
                        }
                    }
                }
            }
            .onChange(of: viewModel.filteredHistory.count) { _ in
                historyPage = min(historyPage, totalPages - 1)
            }
        } label: {
            Label(strings.specificationHistory, systemImage: "clock.arrow.circlepath")
        }
    }
}

private struct HistoryRowView: View {
    let record: HistoryRecord
    @ObservedObject var viewModel: AppViewModel
    let restoreDisabled: Bool

    var body: some View {
        let strings = viewModel.strings

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(record.label)
                            .font(.headline)

                        KindTag(kind: record.kind, strings: strings)
                    }

                    Text(strings.unitSummary(record.snapshot))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(strings.frequencySummary(record.snapshot.frequencyHz) + " • " + strings.runDurationSummary(record.snapshot.runDurationSeconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.restoreHistory(record.id, mode: .appendNew)
                } label: {
                    ActionLabel(title: strings.restoreAsNew, systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(restoreDisabled)

                Button {
                    viewModel.restoreHistory(record.id, mode: .replaceSelected)
                } label: {
                    ActionLabel(title: strings.replaceSelected, systemImage: "square.and.pencil")
                }
                .disabled(viewModel.selectedUnit == nil || restoreDisabled)

                Button(role: .destructive) {
                    viewModel.removeHistoryRecord(id: record.id)
                } label: {
                    ActionLabel(title: strings.deleteSavedSpec, systemImage: "trash")
                }
                .disabled(restoreDisabled)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CountdownOverlayView: View {
    let state: AppViewModel.CountdownState
    let strings: AppStrings

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(state.label)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("\(state.secondsRemaining)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(strings.countdownOverlayHint)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(radius: 18)
        }
        .allowsHitTesting(false)
    }
}

private struct KindTag: View {
    let kind: ClickUnitKind
    let strings: AppStrings

    var body: some View {
        Text(strings.kindDisplayName(kind))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
    }
}
