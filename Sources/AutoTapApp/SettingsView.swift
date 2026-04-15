import AppKit
import AutoTapCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    private var startupCountdownBinding: Binding<Int> {
        Binding(
            get: { viewModel.startupCountdownSeconds },
            set: { viewModel.startupCountdownSeconds = $0 }
        )
    }

    private var autoSaveBinding: Binding<Bool> {
        Binding(
            get: { viewModel.autoSaveExecutedUnitsToHistory },
            set: { viewModel.autoSaveExecutedUnitsToHistory = $0 }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { viewModel.appLanguage },
            set: { viewModel.appLanguage = $0 }
        )
    }

    var body: some View {
        let strings = viewModel.strings

        Form {
            Section(strings.generalSettings) {
                Picker(strings.languageSetting, selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(strings.languageDisplayName(language))
                            .tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(strings.automationSettings) {
                HStack(spacing: 12) {
                    Text(strings.startupCountdown)
                    Spacer()
                    BufferedIntField(
                        title: "",
                        value: startupCountdownBinding,
                        width: 72
                    )
                    Text(strings.seconds)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Stepper("", value: startupCountdownBinding, in: 0 ... 60, step: 1)
                        .labelsHidden()
                }

                Text(strings.countdownHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle(strings.autoSaveExecutedUnits, isOn: autoSaveBinding)
            }

            Section(strings.windowSectionTitle) {
                Text(strings.windowSizingDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(strings.miniBarDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        MiniBarWindowController.shared.show(viewModel: viewModel)
                    } label: {
                        Label(strings.launchMiniBar, systemImage: "rectangle.compress.vertical")
                    }

                    Button {
                        MiniBarWindowController.shared.restoreFullWindow()
                    } label: {
                        Label(strings.restoreMainWindow, systemImage: "rectangle.expand.vertical")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 460, minHeight: 320)
    }
}
