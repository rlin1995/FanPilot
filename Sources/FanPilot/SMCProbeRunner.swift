import Foundation

struct ProbeSnapshot: Codable {
    var modelIdentifier: String
    var sensors: [TemperatureSensor]
    var fans: [FanReading]
}

final class SMCProbeRunner {
    static let installedHelperPath = "/Library/PrivilegedHelperTools/com.local.FanPilot.SMCProbe"
    private let bundledExecutableURL: URL?

    init() {
        bundledExecutableURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("FanPilotSMCProbe")
    }

    var isPrivilegedHelperInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Self.installedHelperPath)
    }

    func snapshot(timeout: TimeInterval = 4) throws -> ProbeSnapshot {
        try run(arguments: ["snapshot"], timeout: timeout)
    }

    func apply(mode: CoolingMode, fans: [FanReading], timeout: TimeInterval = 4) throws {
        let payload = try JSONEncoder().encode(ProbeApplyRequest(mode: mode, fans: fans))
        let payloadText = String(data: payload, encoding: .utf8) ?? "{}"
        let _: ProbeStatus = try run(arguments: ["apply", payloadText], timeout: timeout)
    }

    func applyForce(mode: CoolingMode, fans: [FanReading], timeout: TimeInterval = 4) throws {
        let payload = try JSONEncoder().encode(ProbeApplyRequest(mode: mode, fans: fans))
        let payloadText = String(data: payload, encoding: .utf8) ?? "{}"
        let _: ProbeStatus = try run(arguments: ["apply-force", payloadText], timeout: timeout)
    }

    func applyModeKeys(mode: CoolingMode, fans: [FanReading], timeout: TimeInterval = 4) throws {
        let payload = try JSONEncoder().encode(ProbeApplyRequest(mode: mode, fans: fans))
        let payloadText = String(data: payload, encoding: .utf8) ?? "{}"
        let _: ProbeStatus = try run(arguments: ["apply-mode", payloadText], timeout: timeout)
    }

    func applyMinimum(mode: CoolingMode, fans: [FanReading], timeout: TimeInterval = 4) throws {
        let payload = try JSONEncoder().encode(ProbeApplyRequest(mode: mode, fans: fans))
        let payloadText = String(data: payload, encoding: .utf8) ?? "{}"
        let _: ProbeStatus = try run(arguments: ["apply-min", payloadText], timeout: timeout)
    }

    func restoreMinimums(fans: [FanReading], timeout: TimeInterval = 4) throws {
        let payload = try JSONEncoder().encode(ProbeApplyRequest(mode: .automatic, fans: fans))
        let payloadText = String(data: payload, encoding: .utf8) ?? "{}"
        let _: ProbeStatus = try run(arguments: ["restore-min", payloadText], timeout: timeout)
    }

    func restoreAutomatic(timeout: TimeInterval = 4) throws {
        let _: ProbeStatus = try run(arguments: ["restore"], timeout: timeout)
    }

    func probe(timeout: TimeInterval = 4) throws {
        let _: ProbeStatus = try run(arguments: ["probe"], timeout: timeout)
    }

    func diagnose(timeout: TimeInterval = 4) throws -> String {
        try runText(arguments: ["diagnose"], timeout: timeout)
    }

    func fanKeys(timeout: TimeInterval = 8) throws -> String {
        try runText(arguments: ["fan-keys"], timeout: timeout)
    }

    func installPrivilegedHelper() throws {
        guard let bundledExecutableURL,
              FileManager.default.isExecutableFile(atPath: bundledExecutableURL.path) else {
            throw HardwareControlError.smc("SMC 探测工具未打包")
        }

        let source = bundledExecutableURL.path.shellQuoted
        let target = Self.installedHelperPath.shellQuoted
        let command = [
            "mkdir -p /Library/PrivilegedHelperTools",
            "cp \(source) \(target)",
            "xattr -cr \(target)",
            "chown root:wheel \(target)",
            "chmod 4755 \(target)"
        ].joined(separator: " && ")
        try runAppleScriptAdminCommand(command, timeout: 30)
    }

    func uninstallPrivilegedHelper() throws {
        guard FileManager.default.fileExists(atPath: Self.installedHelperPath) else {
            return
        }
        let command = "rm -f \(Self.installedHelperPath.shellQuoted)"
        try runAppleScriptAdminCommand(command, timeout: 30)
    }

    private func run<T: Decodable>(arguments: [String], timeout: TimeInterval) throws -> T {
        guard let executableURL = activeExecutableURL else {
            throw HardwareControlError.smc("SMC 探测工具未打包")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.03)
        }
        if process.isRunning {
            process.terminate()
            throw HardwareControlError.smc("SMC 探测超时")
        }

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = errorText.isEmpty ? "SMC 探测进程退出：\(process.terminationStatus)" : errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HardwareControlError.smc(message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: outputData)
        } catch {
            throw HardwareControlError.smc("SMC 探测返回无法解析")
        }
    }

    private func runText(arguments: [String], timeout: TimeInterval) throws -> String {
        guard let executableURL = activeExecutableURL else {
            throw HardwareControlError.smc("SMC 探测工具未打包")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.03)
        }
        if process.isRunning {
            process.terminate()
            throw HardwareControlError.smc("SMC 诊断超时")
        }

        let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = errorText.isEmpty ? "SMC 诊断进程退出：\(process.terminationStatus)" : errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HardwareControlError.smc(message)
        }
        return outputText
    }

    private var activeExecutableURL: URL? {
        if isPrivilegedHelperInstalled {
            return URL(fileURLWithPath: Self.installedHelperPath)
        }
        guard let bundledExecutableURL,
              FileManager.default.isExecutableFile(atPath: bundledExecutableURL.path) else {
            return nil
        }
        return bundledExecutableURL
    }

    private func runAppleScriptAdminCommand(_ command: String, timeout: TimeInterval) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \(command.appleScriptQuoted) with administrator privileges"
        ]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw HardwareControlError.smc("管理员授权超时")
        }

        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = errorText.isEmpty ? "管理员授权失败：\(process.terminationStatus)" : errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HardwareControlError.smc(message)
        }
    }
}

struct ProbeStatus: Codable {
    var ok: Bool
}

struct ProbeApplyRequest: Codable {
    var mode: CoolingMode
    var fans: [FanReading]
}

private extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    var appleScriptQuoted: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
