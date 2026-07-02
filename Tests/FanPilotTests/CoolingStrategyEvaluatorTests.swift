import XCTest
@testable import FanPilot

final class CoolingStrategyEvaluatorTests: XCTestCase {
    private let rules = [
        CoolingRule(threshold: 0, mode: .automatic),
        CoolingRule(threshold: 60, mode: .quiet),
        CoolingRule(threshold: 70, mode: .low),
        CoolingRule(threshold: 82, mode: .medium),
        CoolingRule(threshold: 92, mode: .high)
    ]

    func testUpshiftIsNotBlockedByHysteresis() {
        XCTAssertEqual(mode(at: 70, current: .quiet), .low)
        XCTAssertEqual(mode(at: 82, current: .low), .medium)
        XCTAssertEqual(mode(at: 92, current: .medium), .high)
    }

    func testDownshiftWaitsUntilHysteresisBoundary() {
        XCTAssertEqual(mode(at: 78, current: .medium), .medium)
        XCTAssertEqual(mode(at: 77, current: .medium), .low)
    }

    func testEmergencyTemperatureAlwaysUsesFullSpeed() {
        XCTAssertEqual(mode(at: 95, current: .automatic), .full)
        XCTAssertEqual(mode(at: 96, current: .high), .full)
    }

    func testTemperatureBelowFirstRuleUsesAutomatic() {
        let rulesWithoutBaseline = [CoolingRule(threshold: 60, mode: .quiet)]
        let result = CoolingStrategyEvaluator.mode(
            for: 45,
            rules: rulesWithoutBaseline,
            currentMode: .automatic,
            hysteresis: 5,
            emergencyTemperature: 95
        )
        XCTAssertEqual(result, .automatic)
    }

    private func mode(at temperature: Double, current: CoolingMode) -> CoolingMode {
        CoolingStrategyEvaluator.mode(
            for: temperature,
            rules: rules,
            currentMode: current,
            hysteresis: 5,
            emergencyTemperature: 95
        )
    }
}

final class CustomStrategyPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FanPilotTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSavingCustomStrategyPreservesItsName() {
        let store = FanPilotStore(defaults: defaults)
        store.setPreset(.custom)
        var draft = store.strategy
        draft.name = "散热优先"

        store.saveStrategy(draft)

        XCTAssertEqual(store.selectedPreset, .custom)
        XCTAssertEqual(store.strategy.name, "散热优先")
    }

    func testCustomStrategySurvivesPresetChangesAndRelaunch() {
        let store = FanPilotStore(defaults: defaults)
        store.setPreset(.custom)
        var draft = store.strategy
        draft.name = "夜间策略"
        draft.hysteresis = 9
        draft.rules = [
            CoolingRule(threshold: 72, mode: .low),
            CoolingRule(threshold: 55, mode: .quiet)
        ]
        store.saveStrategy(draft)
        let expected = store.strategy

        store.setPreset(.daily)
        store.setPreset(.custom)

        XCTAssertEqual(store.strategy, expected)

        let relaunchedStore = FanPilotStore(defaults: defaults)
        XCTAssertEqual(relaunchedStore.selectedPreset, .custom)
        XCTAssertEqual(relaunchedStore.strategy, expected)
    }

    func testModifiedPresetKeepsItsNameAndShowsModifiedState() {
        let store = FanPilotStore(defaults: defaults)
        store.setPreset(.daily)
        var draft = store.strategy
        draft.name = "不应保存的名称"
        draft.hysteresis = 9

        store.saveStrategy(draft)

        XCTAssertEqual(store.selectedPreset, .daily)
        XCTAssertEqual(store.strategy.name, "日常办公")
        XCTAssertEqual(store.currentStrategyName, "日常办公 *")
        XCTAssertTrue(store.modifiedPresets.contains(.daily))

        store.setPreset(.externalDisplay)
        store.setPreset(.daily)
        XCTAssertEqual(store.strategy.hysteresis, 9)

        let relaunchedStore = FanPilotStore(defaults: defaults)
        XCTAssertEqual(relaunchedStore.selectedPreset, .daily)
        XCTAssertEqual(relaunchedStore.strategy.hysteresis, 9)
        XCTAssertTrue(relaunchedStore.modifiedPresets.contains(.daily))
    }

    func testRestoringPresetDefaultsClearsModifiedState() {
        let store = FanPilotStore(defaults: defaults)
        var draft = store.strategy
        draft.hysteresis = 9
        store.saveStrategy(draft)

        store.restoreCurrentPresetDefaults()

        XCTAssertFalse(store.modifiedPresets.contains(.daily))
        XCTAssertEqual(store.currentStrategyName, "日常办公")
        XCTAssertTrue(store.strategy.matchesDefaults(for: .daily))
    }

    func testPresetSwitchPublishesMatchingStrategyAndFeedback() {
        let store = FanPilotStore(defaults: defaults)

        store.setPreset(.externalDisplay)

        XCTAssertEqual(store.selectedPreset, .externalDisplay)
        XCTAssertEqual(store.strategy.name, "外接显示器")
        XCTAssertEqual(store.strategyApplicationPhase, .switching(.externalDisplay))
    }

    func testRestoringCustomDefaultsResetsSavedName() {
        let store = FanPilotStore(defaults: defaults)
        store.setPreset(.custom)
        var draft = store.strategy
        draft.name = "散热优先"
        store.saveStrategy(draft)

        store.restoreCurrentPresetDefaults()

        XCTAssertEqual(store.strategy.name, "自定义")
        XCTAssertEqual(store.displayedTitle(for: .custom), "自定义")
    }
}
