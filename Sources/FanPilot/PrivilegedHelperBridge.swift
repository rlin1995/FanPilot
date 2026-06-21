import Foundation

protocol FanPilotHelperControlling {
    var statusText: String { get }
    func installIfNeeded() throws
    func apply(mode: CoolingMode, fans: [FanReading]) throws
    func restoreAutomatic() throws
    func uninstall() throws
}

final class DirectSMCHelperBridge: FanPilotHelperControlling {
    private let client = AppleSMCClient()

    var statusText: String {
        "内置 SMC 客户端"
    }

    func installIfNeeded() throws {
        try client.open().probe()
    }

    func apply(mode: CoolingMode, fans: [FanReading]) throws {
        let smc = try client.open()
        if mode == .automatic {
            try smc.restoreAutomaticFanControl()
        } else {
            try smc.setFans(mode: mode, fans: fans)
        }
    }

    func restoreAutomatic() throws {
        try client.open().restoreAutomaticFanControl()
    }

    func uninstall() throws {
        try restoreAutomatic()
    }
}

final class PrivilegedXPCPlaceholderBridge: FanPilotHelperControlling {
    var statusText: String {
        "等待授权 helper"
    }

    func installIfNeeded() throws {
        throw HardwareControlError.smc("授权 helper 尚未打包")
    }

    func apply(mode: CoolingMode, fans: [FanReading]) throws {
        throw HardwareControlError.smc("授权 helper 尚未连接")
    }

    func restoreAutomatic() throws {
        throw HardwareControlError.smc("授权 helper 尚未连接")
    }

    func uninstall() throws {
        throw HardwareControlError.smc("授权 helper 尚未安装")
    }
}
