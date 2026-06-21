import Foundation
import IOKit

private let kSMCHandleYPCEvent: UInt32 = 2
private let kSMCReadKey: UInt8 = 5
private let kSMCWriteKey: UInt8 = 6
private let kSMCGetKeyFromIndex: UInt8 = 8
private let kSMCGetKeyInfo: UInt8 = 9

final class AppleSMCClient {
    func open() throws -> AppleSMCConnection {
        let matching = IOServiceMatching("AppleSMC")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            throw HardwareControlError.smc("找不到 AppleSMC 服务")
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else {
            throw HardwareControlError.smc("无法打开 AppleSMC：\(formatIOReturn(result))")
        }
        return AppleSMCConnection(connection: connection)
    }
}

final class AppleSMCConnection {
    private let connection: io_connect_t

    init(connection: io_connect_t) {
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    func readKnownTemperatureSensors() -> [TemperatureSensor] {
        knownTemperatureKeys.compactMap { descriptor in
            guard let value = try? readValue(key: descriptor.key),
                  let temperature = value.temperature,
                  temperature.isFinite,
                  (-40...130).contains(temperature) else {
                return nil
            }
            return TemperatureSensor(
                id: descriptor.key,
                name: descriptor.name,
                category: descriptor.category,
                temperature: temperature,
                isFavorite: descriptor.favorite
            )
        }
    }

    func probe() throws {
        _ = try readKeyInfo(key: "FNum")
    }

    func readFans() -> [FanReading] {
        let count = Int(min((try? readValue(key: "FNum").integer) ?? 2, 8))
        let fanCount = max(0, min(count, 8))
        return (0..<fanCount).compactMap { index in
            let prefix = "F\(index)"
            guard let current = try? readValue(key: "\(prefix)Ac").rpm,
                  let safeCurrent = saneRPM(current) else {
                return nil
            }
            let minimum = saneRPM((try? readValue(key: "\(prefix)Mn").rpm) ?? 0) ?? 0
            let maximum = saneRPM((try? readValue(key: "\(prefix)Mx").rpm) ?? max(safeCurrent, minimum)) ?? max(safeCurrent, minimum)
            return FanReading(
                id: "\(prefix)Ac",
                name: index == 0 ? "Left side" : index == 1 ? "Right side" : "Fan \(index + 1)",
                minimumRPM: Int(minimum.rounded()),
                currentRPM: Int(safeCurrent.rounded()),
                maximumRPM: Int(maximum.rounded()),
                mode: .automatic
            )
        }
    }

    func diagnosticLines() -> [String] {
        let keys = ["FNum", "FS! ", "F0Ac", "F0Mn", "F0Mx", "F0Tg", "F1Ac", "F1Mn", "F1Mx", "F1Tg", "TC0P", "TC1C", "TB0T", "TW0P"]
        return keys.map { key in
            do {
                let value = try readValue(key: key)
                let bytes = value.bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                return "\(key) type=\(value.dataType) bytes=\(bytes)"
            } catch {
                return "\(key) error=\(error.localizedDescription)"
            }
        }
    }

    func fanKeyDiagnosticLines() -> [String] {
        var lines = ["Known fan/control keys:"]
        for key in ["FNum", "FS! ", "F0Ac", "F0Mn", "F0Mx", "F0Tg", "F1Ac", "F1Mn", "F1Mx", "F1Tg", "F0Md", "F1Md", "F0ID", "F1ID"] {
            lines.append(describeKey(key))
        }

        lines.append("")
        lines.append("Enumerated fan-like keys:")
        do {
            let count = Int((try readValue(key: "#KEY").integer) ?? 0)
            let limit = min(count, 4096)
            for index in 0..<limit {
                guard let key = try? keyAt(index: index) else { continue }
                if isFanLikeKey(key) {
                    lines.append(describeKey(key))
                }
            }
            if count > limit {
                lines.append("... truncated \(count - limit) keys")
            }
        } catch {
            lines.append("#KEY error=\(error.localizedDescription)")
        }
        return lines
    }

    func setFans(mode: CoolingMode, fans: [FanReading]) throws {
        guard !fans.isEmpty else {
            throw HardwareControlError.smc("未检测到风扇")
        }
        for (index, fan) in fans.enumerated() {
            let target = targetRPM(for: mode, fan: fan)
            try writeRPM(key: "F\(index)Tg", value: Double(target))
        }
    }

    func setFansWithModeKeys(mode: CoolingMode, fans: [FanReading]) throws {
        guard !fans.isEmpty else {
            throw HardwareControlError.smc("未检测到风扇")
        }
        for (index, fan) in fans.enumerated() {
            let target = targetRPM(for: mode, fan: fan)
            try writeUInt8(key: "F\(index)Md", value: 1)
            try writeRPM(key: "F\(index)Tg", value: Double(target))
        }
    }

    func restoreAutomaticFanControl() throws {
        let fans = readFans()
        if !fans.isEmpty {
            for (index, fan) in fans.enumerated() {
                try? writeRPM(key: "F\(index)Tg", value: Double(fan.minimumRPM))
                try? writeUInt8(key: "F\(index)Md", value: 0)
            }
        }
        try? writeUInt16(key: "FS! ", value: 0)
    }

    func setFansWithForceMask(mode: CoolingMode, fans: [FanReading]) throws {
        guard !fans.isEmpty else {
            throw HardwareControlError.smc("未检测到风扇")
        }
        var forceMask: UInt16 = 0
        for (index, fan) in fans.enumerated() {
            forceMask |= UInt16(1 << index)
            let target = targetRPM(for: mode, fan: fan)
            try writeRPM(key: "F\(index)Tg", value: Double(target))
        }
        try writeUInt16(key: "FS! ", value: forceMask)
    }

    func setFanMinimums(mode: CoolingMode, fans: [FanReading]) throws {
        guard !fans.isEmpty else {
            throw HardwareControlError.smc("未检测到风扇")
        }
        for (index, fan) in fans.enumerated() {
            let target = targetRPM(for: mode, fan: fan)
            try writeRPM(key: "F\(index)Mn", value: Double(target))
        }
    }

    func restoreFanMinimums(fans: [FanReading]) throws {
        guard !fans.isEmpty else {
            throw HardwareControlError.smc("未检测到风扇")
        }
        for (index, fan) in fans.enumerated() {
            try writeRPM(key: "F\(index)Mn", value: Double(fan.minimumRPM))
        }
    }

    private func targetRPM(for mode: CoolingMode, fan: FanReading) -> Int {
        guard mode != .automatic else { return fan.minimumRPM }
        let span = max(0, fan.maximumRPM - fan.minimumRPM)
        let rpm = fan.minimumRPM + Int(Double(span) * mode.rpmRatio)
        return min(fan.maximumRPM, max(fan.minimumRPM, rpm))
    }

    private func saneRPM(_ value: Double) -> Double? {
        guard value.isFinite, (0...20000).contains(value) else {
            return nil
        }
        return value
    }

    func readValue(key: String) throws -> SMCValue {
        let info = try readKeyInfo(key: key)
        var input = SMCKeyData()
        input.key = fourCharCode(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = kSMCReadKey
        let output = try call(input)
        return SMCValue(
            key: key,
            dataType: stringFromFourCharCode(info.dataType),
            bytes: output.bytesArray.prefix(Int(info.dataSize)).map { $0 }
        )
    }

    private func keyAt(index: Int) throws -> String {
        var input = SMCKeyData()
        input.data8 = kSMCGetKeyFromIndex
        input.data32 = UInt32(index)
        let output = try call(input)
        guard output.result == 0 else {
            throw HardwareControlError.smc("读取 key index \(index) 失败：\(output.result)")
        }
        return stringFromFourCharCode(output.key)
    }

    private func describeKey(_ key: String) -> String {
        do {
            let info = try readKeyInfo(key: key)
            let type = stringFromFourCharCode(info.dataType)
            let value = try? readValue(key: key)
            let bytes = value?.bytes.map { String(format: "%02x", $0) }.joined(separator: " ") ?? "-"
            return "\(key) size=\(info.dataSize) type=\(type) attr=\(info.dataAttributes) bytes=\(bytes)"
        } catch {
            return "\(key) error=\(error.localizedDescription)"
        }
    }

    private func isFanLikeKey(_ key: String) -> Bool {
        key == "FS! " ||
        key == "FNum" ||
        key.hasPrefix("F0") ||
        key.hasPrefix("F1") ||
        key.hasPrefix("F2") ||
        key.hasPrefix("F3") ||
        key.localizedCaseInsensitiveContains("fan")
    }

    private func readKeyInfo(key: String) throws -> SMCKeyInfoData {
        var input = SMCKeyData()
        input.key = fourCharCode(key)
        input.data8 = kSMCGetKeyInfo
        let output = try call(input)
        guard output.result == 0 else {
            throw HardwareControlError.smc("读取 \(key) 信息失败：\(output.result)")
        }
        return output.keyInfo
    }

    private func writeFPE2(key: String, value: Double) throws {
        let raw = UInt16(max(0, min(65535, Int(value * 4))))
        try write(key: key, dataType: "fpe2", bytes: [UInt8(raw >> 8), UInt8(raw & 0xff)])
    }

    private func writeRPM(key: String, value: Double) throws {
        let info = try readKeyInfo(key: key)
        let dataType = stringFromFourCharCode(info.dataType)
        switch dataType {
        case "flt ":
            try writeFloat32(key: key, value: Float(value))
        case "fpe2":
            try writeFPE2(key: key, value: value)
        default:
            throw HardwareControlError.smc("\(key) 使用暂不支持的风扇目标类型：\(dataType)")
        }
    }

    private func writeFloat32(key: String, value: Float) throws {
        let raw = value.bitPattern
        try write(
            key: key,
            dataType: "flt ",
            bytes: [
                UInt8(raw & 0xff),
                UInt8((raw >> 8) & 0xff),
                UInt8((raw >> 16) & 0xff),
                UInt8((raw >> 24) & 0xff)
            ]
        )
    }

    private func writeUInt16(key: String, value: UInt16) throws {
        try write(key: key, dataType: "ui16", bytes: [UInt8(value >> 8), UInt8(value & 0xff)], allowMissingKeyInfo: key == "FS! ")
    }

    private func writeUInt8(key: String, value: UInt8) throws {
        try write(key: key, dataType: "ui8 ", bytes: [value])
    }

    private func write(key: String, dataType: String, bytes: [UInt8], allowMissingKeyInfo: Bool = false) throws {
        let info: SMCKeyInfoData
        do {
            info = try readKeyInfo(key: key)
        } catch {
            guard allowMissingKeyInfo else {
                throw error
            }
            info = SMCKeyInfoData(dataSize: UInt32(bytes.count), dataType: fourCharCode(dataType), dataAttributes: 0)
        }
        var input = SMCKeyData()
        input.key = fourCharCode(key)
        input.keyInfo = info
        input.keyInfo.dataSize = UInt32(bytes.count)
        input.keyInfo.dataType = fourCharCode(dataType)
        input.data8 = kSMCWriteKey
        input.setBytes(bytes)
        let output = try call(input)
        guard output.result == 0 else {
            throw HardwareControlError.smc("写入 \(key) 失败：\(output.result)")
        }
    }

    private func call(_ input: SMCKeyData) throws -> SMCKeyData {
        var input = input
        var output = SMCKeyData()
        var outputSize = 80
        let result = input.withUnsafeMutableRawBufferPointer { inputBuffer in
            output.withUnsafeMutableRawBufferPointer { outputBuffer in
                IOConnectCallStructMethod(
                    connection,
                    kSMCHandleYPCEvent,
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    outputBuffer.baseAddress,
                    &outputSize
                )
            }
        }
        guard result == KERN_SUCCESS else {
            throw HardwareControlError.smc("AppleSMC 调用失败：\(formatIOReturn(result))")
        }
        return output
    }
}

private func formatIOReturn(_ result: kern_return_t) -> String {
    let hex = String(format: "0x%08x", UInt32(bitPattern: result))
    switch result {
    case -536870207:
        return "\(result) / \(hex)，AppleSMC 不支持当前调用，可能需要授权 helper 或新版调用方式"
    case -536870174:
        return "\(result) / \(hex)，系统拒绝打开 AppleSMC，可能需要授权 helper"
    case -536870206:
        return "\(result) / \(hex)，AppleSMC 参数格式不匹配"
    default:
        return "\(result) / \(hex)"
    }
}

private struct TemperatureDescriptor {
    let key: String
    let name: String
    let category: SensorCategory
    let favorite: Bool
}

private let knownTemperatureKeys: [TemperatureDescriptor] = [
    TemperatureDescriptor(key: "TC0P", name: "CPU Core (average)", category: .cpu, favorite: true),
    TemperatureDescriptor(key: "TC0E", name: "CPU PECI", category: .cpu, favorite: false),
    TemperatureDescriptor(key: "TC1C", name: "CPU Core 1", category: .cpu, favorite: true),
    TemperatureDescriptor(key: "TC2C", name: "CPU Core 2", category: .cpu, favorite: false),
    TemperatureDescriptor(key: "TC3C", name: "CPU Core 3", category: .cpu, favorite: false),
    TemperatureDescriptor(key: "TC4C", name: "CPU Core 4", category: .cpu, favorite: false),
    TemperatureDescriptor(key: "TG0P", name: "GPU Proximity", category: .cpu, favorite: false),
    TemperatureDescriptor(key: "TB0T", name: "Battery Max", category: .battery, favorite: true),
    TemperatureDescriptor(key: "TB1T", name: "Battery Sensor 1", category: .battery, favorite: false),
    TemperatureDescriptor(key: "TB2T", name: "Battery Sensor 2", category: .battery, favorite: false),
    TemperatureDescriptor(key: "TW0P", name: "Airport Proximity", category: .wireless, favorite: true),
    TemperatureDescriptor(key: "TH0x", name: "Palm Rest", category: .enclosure, favorite: false),
    TemperatureDescriptor(key: "Ts0P", name: "Memory Proximity", category: .other, favorite: false),
    TemperatureDescriptor(key: "TS0P", name: "SSD", category: .storage, favorite: true)
]

struct SMCValue {
    let key: String
    let dataType: String
    let bytes: [UInt8]

    var temperature: Double? {
        switch dataType {
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int8(bitPattern: bytes[0])) + Double(bytes[1]) / 256.0
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw = littleEndianUInt32(bytes)
            let value = Double(Float(bitPattern: raw))
            return value.isFinite ? value : nil
        default:
            return nil
        }
    }

    var rpm: Double? {
        switch dataType {
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4.0
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw = littleEndianUInt32(bytes)
            let value = Double(Float(bitPattern: raw))
            return value.isFinite ? value : nil
        default:
            return integer.map(Double.init)
        }
    }

    var integer: UInt32? {
        switch bytes.count {
        case 1:
            return UInt32(bytes[0])
        case 2:
            return UInt32(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case 4:
            return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        default:
            return nil
        }
    }
}

private func littleEndianUInt32(_ bytes: [UInt8]) -> UInt32 {
    UInt32(bytes[0])
        | UInt32(bytes[1]) << 8
        | UInt32(bytes[2]) << 16
        | UInt32(bytes[3]) << 24
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    private static let byteCount = 80
    private var storage = [UInt8](repeating: 0, count: byteCount)

    var key: UInt32 {
        get { readUInt32(at: 0) }
        set { writeUInt32(newValue, at: 0) }
    }

    var keyInfo: SMCKeyInfoData {
        get {
            SMCKeyInfoData(
                dataSize: readUInt32(at: 28),
                dataType: readUInt32(at: 32),
                dataAttributes: storage[36]
            )
        }
        set {
            writeUInt32(newValue.dataSize, at: 28)
            writeUInt32(newValue.dataType, at: 32)
            storage[36] = newValue.dataAttributes
        }
    }

    var result: UInt8 {
        get { storage[40] }
        set { storage[40] = newValue }
    }

    var data8: UInt8 {
        get { storage[42] }
        set { storage[42] = newValue }
    }

    var data32: UInt32 {
        get { readUInt32(at: 44) }
        set { writeUInt32(newValue, at: 44) }
    }

    var bytesArray: [UInt8] {
        Array(storage[48..<80])
    }

    mutating func setBytes(_ newBytes: [UInt8]) {
        for index in 48..<80 {
            storage[index] = 0
        }
        for (index, byte) in newBytes.prefix(32).enumerated() {
            storage[48 + index] = byte
        }
    }

    mutating func withUnsafeMutableRawBufferPointer<R>(_ body: (UnsafeMutableRawBufferPointer) throws -> R) rethrows -> R {
        try storage.withUnsafeMutableBytes(body)
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        UInt32(storage[offset])
            | UInt32(storage[offset + 1]) << 8
            | UInt32(storage[offset + 2]) << 16
            | UInt32(storage[offset + 3]) << 24
    }

    private mutating func writeUInt32(_ value: UInt32, at offset: Int) {
        storage[offset] = UInt8(value & 0xff)
        storage[offset + 1] = UInt8((value >> 8) & 0xff)
        storage[offset + 2] = UInt8((value >> 16) & 0xff)
        storage[offset + 3] = UInt8((value >> 24) & 0xff)
    }
}

private func fourCharCode(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for byte in Array(string.utf8.prefix(4)) {
        result = (result << 8) + UInt32(byte)
    }
    for _ in string.utf8.count..<4 {
        result <<= 8
    }
    return result
}

private func stringFromFourCharCode(_ code: UInt32) -> String {
    let bytes = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff)
    ]
    return String(bytes: bytes, encoding: .ascii) ?? ""
}
