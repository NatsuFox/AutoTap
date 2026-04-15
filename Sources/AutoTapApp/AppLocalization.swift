import Foundation
import AutoTapCore

struct AppStrings {
    let language: AppLanguage

    init(preferredLanguage: AppLanguage, locale: Locale = .current) {
        language = Self.resolvedLanguage(from: preferredLanguage, locale: locale)
    }

    static func resolvedLanguage(from preferredLanguage: AppLanguage, locale: Locale = .current) -> AppLanguage {
        switch preferredLanguage {
        case .system:
            if let languageCode = locale.language.languageCode?.identifier, languageCode.hasPrefix("zh") {
                return .simplifiedChinese
            }
            if locale.identifier.hasPrefix("zh") {
                return .simplifiedChinese
            }
            return .english
        case .english, .simplifiedChinese:
            return preferredLanguage
        }
    }

    private func tr(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }

    private func decimalString(_ value: Double, maximumFractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    func languageDisplayName(_ appLanguage: AppLanguage) -> String {
        switch appLanguage {
        case .system:
            return tr("Follow System", "跟随系统")
        case .english:
            return tr("English", "英文")
        case .simplifiedChinese:
            return tr("Simplified Chinese", "简体中文")
        }
    }

    func kindDisplayName(_ kind: ClickUnitKind) -> String {
        switch kind {
        case .singlePoint:
            return addSinglePoint
        case .pointGroup:
            return addPointGroup
        }
    }

    func defaultSinglePointUnitName(_ index: Int) -> String {
        tr("Single Point \(index)", "单点 \(index)")
    }

    func defaultPointGroupUnitName(_ index: Int) -> String {
        tr("Point Group \(index)", "点组 \(index)")
    }

    func defaultPointName(_ index: Int? = nil) -> String {
        if let index {
            return tr("Point \(index)", "点位 \(index)")
        }
        return tr("Point", "点位")
    }

    func coordinatesSummary(x: Double, y: Double) -> String {
        "X: \(Int(x.rounded()))  Y: \(Int(y.rounded()))"
    }

    func coordinatesSummary(_ point: ScreenPoint) -> String {
        coordinatesSummary(x: point.x, y: point.y)
    }

    func frequencySummary(_ frequencyHz: Double) -> String {
        "\(decimalString(frequencyHz)) Hz"
    }

    func runDurationSummary(_ seconds: Double) -> String {
        guard seconds > 0 else {
            return tr("No auto-stop", "不自动停止")
        }

        return tr(
            "Auto-stop after \(Int(seconds.rounded()))s",
            "\(Int(seconds.rounded())) 秒后自动停止"
        )
    }

    func unitSummary(_ unit: ClickUnit) -> String {
        switch unit.kind {
        case .singlePoint:
            return coordinatesSummary(unit.singlePoint)
        case .pointGroup:
            return pointsInSequence(unit.groupPoints.count)
        }
    }

    func runProgressSummary(_ remainingSeconds: Int) -> String {
        if remainingSeconds <= 0 {
            return tr("Stopping…", "即将停止…")
        }
        return tr("\(remainingSeconds)s remaining", "剩余 \(remainingSeconds) 秒")
    }

    func startingUnit(_ name: String) -> String {
        tr("Starting \(name)", "正在启动 \(name)")
    }

    func startingUnits(_ count: Int) -> String {
        tr(
            count == 1 ? "Starting 1 unit" : "Starting \(count) units",
            count == 1 ? "正在启动 1 个单元" : "正在启动 \(count) 个单元"
        )
    }

    func historySnapshotLabel(_ unitName: String) -> String {
        tr("\(unitName) Snapshot", "\(unitName) 快照")
    }

    var appTitle: String { tr("AutoTap", "AutoTap") }
    var configuredUnits: String { tr("Configured Units", "已配置单元") }
    var configuredUnitsDescription: String {
        tr(
            "Single points and point groups can be scheduled together. Active clicks are protected by a global Esc stop and a configurable start countdown.",
            "单点和点组可以一起调度运行。连点过程受全局 Esc 紧急停止和可配置启动倒计时保护。"
        )
    }
    var selectUnit: String { tr("Select Unit", "选择单元") }
    var compactLayoutDescription: String {
        tr(
            "When the window becomes narrow, the editor switches to this compact unit selector so the app can stay usable at a much smaller size.",
            "当窗口缩窄后，编辑器会切换到这个紧凑的单元选择区，以便应用在更小尺寸下仍然可用。"
        )
    }
    var add: String { tr("Add", "新增") }
    var addSinglePoint: String { tr("Single Point", "单点") }
    var addPointGroup: String { tr("Point Group", "点组") }
    var startAll: String { tr("Start All", "全部开始") }
    var stopAll: String { tr("Stop All", "全部停止") }
    var openSettings: String { tr("Settings", "设置") }
    var showMiniBar: String { tr("Mini Bar", "迷你栏") }
    var noUnitSelected: String { tr("No Unit Selected", "未选择单元") }
    var noUnitSelectedDescription: String {
        tr(
            "Add a single point unit or a point group to start building your auto-clicker configuration.",
            "新增一个单点或点组单元后即可开始配置自动点击方案。"
        )
    }

    var accessibilityActive: String { tr("Accessibility permission is active.", "辅助功能权限已启用。") }
    var accessibilityRequired: String { tr("Accessibility permission is required before clicking can start.", "开始点击前需要授予辅助功能权限。") }
    var startupCountdown: String { tr("Startup Countdown", "启动倒计时") }
    var seconds: String { tr("Seconds", "秒") }
    var countdownHint: String { tr("0 means no startup delay", "0 表示不延迟启动") }
    var autoSaveExecutedUnits: String { tr("Auto-save executed units to history", "自动将执行过的单元保存到历史") }
    var promptAccessibility: String { tr("Prompt Accessibility", "请求辅助功能权限") }
    var refreshStatus: String { tr("Refresh Status", "刷新状态") }
    var cancelPick: String { tr("Cancel Pick", "取消取点") }
    var cancelCountdown: String { tr("Cancel Countdown", "取消倒计时") }
    var liveCoordinatesPrefix: String { tr("Live coordinates", "实时坐标") }
    var moveCursorToInspectCoordinates: String { tr("Move the cursor to inspect coordinates", "移动鼠标以查看坐标") }
    func liveCoordinates(_ summary: String) -> String { "\(liveCoordinatesPrefix): \(summary)" }
    func countdownActive(_ secondsRemaining: Int) -> String {
        tr(
            "Countdown active: \(secondsRemaining). Press Esc to cancel before clicking starts.",
            "倒计时进行中：\(secondsRemaining)。点击开始前可按 Esc 取消。"
        )
    }
    func countdownShort(_ secondsRemaining: Int) -> String {
        tr("Starts in \(secondsRemaining)s", "\(secondsRemaining) 秒后开始")
    }
    var clickingActiveNow: String { tr("Clicking is active right now. Press Esc to stop immediately.", "当前正在连点。按 Esc 可立即停止。") }
    var safetyControls: String { tr("Safety Controls", "安全控制") }

    var unitSettings: String { tr("Unit Settings", "单元设置") }
    var unitName: String { tr("Unit Name", "单元名称") }
    var frequency: String { tr("Frequency", "频率") }
    var autoStop: String { tr("Auto-stop", "自动停止") }
    var autoStopHint: String {
        tr(
            "0 seconds means this unit keeps running until you stop it manually. A positive value makes only this unit stop when its own timer ends.",
            "0 秒表示该单元会持续运行直到你手动停止。大于 0 时，该单元会在自己的计时结束后自动停止。"
        )
    }
    func timerActive(_ summary: String) -> String { tr("Timer active: \(summary)", "计时进行中：\(summary)") }
    var duplicateUnit: String { tr("Duplicate Unit", "复制单元") }
    var removeUnit: String { tr("Remove Unit", "删除单元") }
    var stopUnit: String { tr("Stop Unit", "停止单元") }
    var startUnit: String { tr("Start Unit", "开始单元") }

    var clickPosition: String { tr("Click Position", "点击位置") }
    var pickFromScreen: String { tr("Pick From Screen", "从屏幕取点") }
    var pickSinglePointPrompt: String { tr("Click anywhere on screen to set the single-point target", "请在屏幕任意位置点击，以设置单点目标") }
    var pickGroupPointPrompt: String { tr("Click anywhere on screen to set this point in the group", "请在屏幕任意位置点击，以设置该点组中的点位") }
    var pointName: String { tr("Point Name", "点位名称") }
    var xAxis: String { tr("X", "X") }
    var yAxis: String { tr("Y", "Y") }

    var pointGroupDescription: String {
        tr(
            "Points are clicked sequentially from top to bottom. Use Pick From Screen to assign each point directly and the arrow buttons to change the order.",
            "点位会按照从上到下的顺序依次点击。可使用屏幕取点直接赋值，也可用箭头按钮调整顺序。"
        )
    }
    var pointGroup: String { tr("Point Group", "点组") }
    var addPoint: String { tr("Add Point", "新增点位") }
    func pointsInSequence(_ count: Int) -> String {
        tr("\(count) points in this sequence", "该序列中共有 \(count) 个点位")
    }
    var moveUp: String { tr("Up", "上移") }
    var moveDown: String { tr("Down", "下移") }
    var removePoint: String { tr("Remove Point", "删除点位") }

    var specificationHistory: String { tr("Specification History", "配置历史") }
    var historyDescription: String {
        tr(
            "History records are stored locally so you can restore old point and group specifications, adjust them, and run them again.",
            "历史记录会保存在本地，便于你恢复旧的点位或点组配置、继续调整并再次运行。"
        )
    }
    var noHistoryYet: String { tr("No history records yet. Start a unit to create one.", "当前还没有历史记录。运行单元后会自动生成。") }
    var autoSaveOffHistoryHint: String {
        tr(
            "Auto-save is off. Enable it above to capture future executed units in history.",
            "自动保存已关闭。请在上方开启它，以便将后续执行过的单元记录到历史中。"
        )
    }
    func historyPage(_ current: Int, _ total: Int) -> String { tr("Page \(current) of \(total)", "第 \(current) / \(total) 页") }
    var previousPage: String { tr("Previous", "上一页") }
    var nextPage: String { tr("Next", "下一页") }
    var restoreAsNew: String { tr("Restore As New", "恢复为新单元") }
    var replaceSelected: String { tr("Replace Selected", "替换当前所选") }
    var deleteSavedSpec: String { tr("Delete Saved Spec", "删除历史配置") }

    var persistenceError: String { tr("Persistence Error", "持久化错误") }
    var dismiss: String { tr("Dismiss", "关闭") }
    var pressEscToCancel: String { tr("Press Esc to cancel", "按 Esc 取消") }
    var countdownOverlayHint: String { tr("Press Esc to cancel before clicking begins", "开始点击前按 Esc 可取消") }

    var settingsTitle: String { tr("Settings", "设置") }
    var generalSettings: String { tr("General", "通用") }
    var automationSettings: String { tr("Automation", "自动化") }
    var appearanceSettings: String { tr("Appearance", "界面") }
    var languageSetting: String { tr("Language", "语言") }
    var windowSectionTitle: String { tr("Window & Mini Bar", "窗口与迷你栏") }
    var launchMiniBar: String { tr("Open Mini Bar", "打开迷你栏") }
    var miniBarDescription: String {
        tr(
            "The mini bar is a floating compact window that keeps the app accessible without sending it to the Dock.",
            "迷你栏是一个悬浮的紧凑窗口，可在不缩入 Dock 的情况下保持应用随时可用。"
        )
    }
    var windowSizingDescription: String {
        tr(
            "The main editor now supports a tighter compact layout when you resize it narrower, so it can stay usable at a much smaller size.",
            "现在当你把主编辑窗口缩窄时，它会切换到更紧凑的布局，从而在更小尺寸下仍然可用。"
        )
    }
    var restoreMainWindow: String { tr("Restore Main Window", "恢复主窗口") }

    var miniBarIdle: String { tr("Idle", "空闲") }
    var miniBarRunning: String { tr("Running", "运行中") }
    var miniBarCountdown: String { tr("Countdown", "倒计时") }
    var restoreFullWindow: String { tr("Restore", "恢复窗口") }
    func activeUnits(_ count: Int) -> String { tr("Active units: \(count)", "运行中单元：\(count)") }
    func totalUnits(_ count: Int) -> String { tr("Total units: \(count)", "单元总数：\(count)") }

    var emergencyStopArmedSummary: String {
        tr(
            "Emergency stop is armed. Press Esc at any time to stop countdowns, pick mode, or active clicking.",
            "紧急停止已启用。你可以随时按 Esc 停止倒计时、退出取点或中止当前连点。"
        )
    }
    var emergencyStopDisarmedSummary: String {
        tr(
            "Emergency stop is not armed. Clicking is blocked until Esc monitoring is active.",
            "紧急停止尚未启用。在 Esc 监控可用之前，点击功能会被阻止。"
        )
    }

    var accessibilityRequiredError: String {
        tr(
            "Accessibility permission is required before AutoTap can start clicking.",
            "在 AutoTap 开始点击前，必须授予辅助功能权限。"
        )
    }

    var emergencyStopRequiredError: String {
        tr(
            "Esc emergency stop is not armed. Clicking is blocked until that safeguard is active.",
            "Esc 紧急停止尚未启用。在该保护可用之前，点击功能会被阻止。"
        )
    }

    var finishScreenPickBeforeStartError: String {
        tr(
            "Finish or cancel screen picking before starting a click run.",
            "开始点击前，请先完成或取消屏幕取点。"
        )
    }

    var stopClickingBeforePickError: String {
        tr(
            "Stop active clicking before picking new coordinates from the screen.",
            "从屏幕重新取点前，请先停止当前连点。"
        )
    }

    var cancelCountdownBeforePickError: String {
        tr(
            "Cancel the active countdown before picking new coordinates.",
            "重新取点前，请先取消当前倒计时。"
        )
    }

    func persistenceSaveFailed(_ path: String) -> String {
        tr(
            "Failed to save AutoTap state to \(path).",
            "无法将 AutoTap 状态保存到 \(path)。"
        )
    }
}
