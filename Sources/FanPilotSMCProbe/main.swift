import Foundation

func writeJSON<T: Encodable>(_ value: T) {
    let data = try! JSONEncoder().encode(value)
    FileHandle.standardOutput.write(data)
}

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let command = CommandLine.arguments.dropFirst().first ?? "snapshot"
let helperProtocolVersion = 2

do {
    switch command {
    case "version":
        writeJSON(ProbeVersion(version: helperProtocolVersion))
    case "probe":
        let smc = try AppleSMCClient().open()
        try smc.probe()
        writeJSON(ProbeStatus(ok: true))
    case "snapshot":
        let smc = try AppleSMCClient().open()
        let sensors = smc.readKnownTemperatureSensors()
        let fans = smc.readFans()
        if sensors.isEmpty && fans.isEmpty {
            fail("AppleSMC 未返回可识别传感器或风扇")
        }
        writeJSON(ProbeSnapshot(
            modelIdentifier: SystemProfiler.modelIdentifier,
            sensors: sensors,
            fans: fans
        ))
    case "diagnose":
        let smc = try AppleSMCClient().open()
        let lines = smc.diagnosticLines()
        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    case "fan-keys":
        let smc = try AppleSMCClient().open()
        let lines = smc.fanKeyDiagnosticLines()
        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    case "apply":
        let smc = try AppleSMCClient().open()
        guard CommandLine.arguments.count >= 3,
              let data = CommandLine.arguments[2].data(using: .utf8) else {
            fail("缺少风扇控制参数")
        }
        let request = try JSONDecoder().decode(ProbeApplyRequest.self, from: data)
        if request.mode == .automatic {
            try smc.restoreAutomaticFanControl()
        } else {
            try smc.setFans(mode: request.mode, fans: request.fans)
        }
        writeJSON(ProbeStatus(ok: true))
    case "apply-force":
        let smc = try AppleSMCClient().open()
        guard CommandLine.arguments.count >= 3,
              let data = CommandLine.arguments[2].data(using: .utf8) else {
            fail("缺少风扇控制参数")
        }
        let request = try JSONDecoder().decode(ProbeApplyRequest.self, from: data)
        try smc.setFansWithForceMask(mode: request.mode, fans: request.fans)
        writeJSON(ProbeStatus(ok: true))
    case "apply-mode":
        let smc = try AppleSMCClient().open()
        guard CommandLine.arguments.count >= 3,
              let data = CommandLine.arguments[2].data(using: .utf8) else {
            fail("缺少风扇控制参数")
        }
        let request = try JSONDecoder().decode(ProbeApplyRequest.self, from: data)
        try smc.setFansWithModeKeys(mode: request.mode, fans: request.fans)
        writeJSON(ProbeStatus(ok: true))
    case "apply-min":
        let smc = try AppleSMCClient().open()
        guard CommandLine.arguments.count >= 3,
              let data = CommandLine.arguments[2].data(using: .utf8) else {
            fail("缺少风扇控制参数")
        }
        let request = try JSONDecoder().decode(ProbeApplyRequest.self, from: data)
        try smc.setFanMinimums(mode: request.mode, fans: request.fans)
        writeJSON(ProbeStatus(ok: true))
    case "restore-min":
        let smc = try AppleSMCClient().open()
        guard CommandLine.arguments.count >= 3,
              let data = CommandLine.arguments[2].data(using: .utf8) else {
            fail("缺少风扇恢复参数")
        }
        let request = try JSONDecoder().decode(ProbeApplyRequest.self, from: data)
        try smc.restoreFanMinimums(fans: request.fans)
        writeJSON(ProbeStatus(ok: true))
    case "restore":
        let smc = try AppleSMCClient().open()
        try smc.restoreAutomaticFanControl()
        writeJSON(ProbeStatus(ok: true))
    default:
        fail("未知 SMC 探测命令：\(command)")
    }
} catch {
    fail(error.localizedDescription)
}

enum SystemProfiler {
    static var modelIdentifier: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
