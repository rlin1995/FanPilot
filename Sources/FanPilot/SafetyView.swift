import SwiftUI

struct SafetyView: View {
    @ObservedObject var store: FanPilotStore

    private var needsHelper: Bool {
        !store.isWriteRestricted && !hasSMCAccess && !store.isControlEnabled && (
            store.helperStatus.contains("helper") ||
            store.smcStatus.contains("拒绝") ||
            store.smcStatus.contains("不可访问") ||
            store.lastWrite.contains("不可用") ||
            store.lastWrite.contains("失败")
        )
    }

    private var hasSMCAccess: Bool {
        store.smcStatus.contains("AppleSMC 可访问") ||
        store.hardwareStatusText.contains("AppleSMC 监控") ||
        store.lastWrite.contains("AppleSMC 检测成功") ||
        store.lastWrite.contains("SMC 诊断完成")
    }

    private var writeRestricted: Bool {
        store.isWriteRestricted || store.smcStatus.contains("写入受限")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "安全与权限", subtitle: "控制风扇需要本地 helper 与管理员授权")

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: store.isControlEnabled ? "checkmark.shield" : writeRestricted ? "exclamationmark.triangle" : needsHelper ? "exclamationmark.shield" : "lock.shield")
                            .font(.largeTitle)
                            .foregroundStyle(store.isControlEnabled ? .green : writeRestricted ? .orange : needsHelper ? .orange : .secondary)
                            .frame(width: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.isControlEnabled ? "风扇控制已启用" : writeRestricted ? "AppleSMC 可读，写入受限" : hasSMCAccess ? "AppleSMC 已可访问" : needsHelper ? "需要管理员授权 helper" : "当前为监控模式")
                                .font(.title3.weight(.semibold))
                            Text(store.isControlEnabled ? "FanPilot 正在按策略评估散热档位。" : writeRestricted ? "FanPilot 已经能读取温度和风扇转速，但当前系统拒绝写入风扇控制 key。应用会保持监控模式。" : hasSMCAccess ? "FanPilot 已经能读取 AppleSMC。你可以先在概览页查看真实温度和转速。" : needsHelper ? "macOS 已拒绝普通进程访问 AppleSMC。下一步需要安装本地授权 helper 后再读取和控制风扇。" : "FanPilot 可以读取温度和风扇转速，但尚未控制风扇。")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text("启用后，FanPilot 会安装一个本地授权 helper，并通过它访问 AppleSMC。FanPilot 只会提高最低风扇转速，不会低于 Apple 默认最低值；任何读取或写入失败都会自动回到监控模式。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        if store.isControlEnabled {
                            fittedButton("恢复 Apple 自动控制") {
                                store.restoreAutomaticControl()
                            }
                            fittedButton("卸载 helper") {
                                store.uninstallHelper()
                            }
                        } else {
                            fittedButton("检测 AppleSMC") {
                                store.detectSMC()
                            }
                            fittedButton("安装/更新授权 helper") {
                                store.enableControl()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    HStack(spacing: 10) {
                        fittedButton("运行诊断") {
                            store.runDiagnostics()
                        }
                        fittedButton("扫描风扇 Key") {
                            store.runFanKeyDiagnostics()
                        }
                        fittedButton("测试目标转速") {
                            store.testTargetWrite()
                        }
                        fittedButton("测试模式 Key") {
                            store.testModeKeyWrite()
                        }
                        fittedButton("测试最低转速") {
                            store.testMinimumWrite()
                        }
                        fittedButton("测试强制控制") {
                            store.testForceWrite()
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: 760, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                if store.canControlFans {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("散热档位")
                            .font(.headline)
                        ForEach(CoolingMode.allCases) { mode in
                            HStack(spacing: 12) {
                                if mode == store.currentStrategyMode {
                                    Button(mode.title) {
                                        store.applyMode(mode)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .frame(width: 84, alignment: .leading)
                                } else {
                                    Button(mode.title) {
                                        store.applyMode(mode)
                                    }
                                    .buttonStyle(.bordered)
                                    .frame(width: 84, alignment: .leading)
                                }
                                Text(store.targetRPMText(for: mode))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: 760, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("状态")
                        .font(.headline)
                    InfoRow(label: "Helper 状态", value: store.helperStatus)
                    InfoRow(label: "SMC 访问", value: store.smcStatus)
                    InfoRow(label: "最后写入", value: store.lastWrite)
                    InfoRow(label: "硬件模式", value: store.hardwareStatusText)
                }
                .padding(18)
                .frame(maxWidth: 760, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                if !store.diagnosticText.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SMC 诊断")
                            .font(.headline)
                        ScrollView {
                            Text(store.diagnosticText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                    }
                    .padding(18)
                    .frame(maxWidth: 760, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func fittedButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct InfoRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
    }
}
