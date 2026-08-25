// swiftlint:disable:this file_name
import BitwardenKit
import BitwardenKitMocks
import BitwardenResources
import XCTest

@testable import BitwardenShared

class AboutViewTests: BitwardenTestCase {
    // MARK: Properties

    let copyrightText = """
    Modified from Bitwarden iOS. You may redistribute it under GNU GPLv3; it comes without warranty.
    F.R.I.D.A.Y. Vault is not affiliated with or endorsed by Bitwarden, Inc.
    Upstream: © Bitwarden Inc. 2015-2023
    """ // No need to be dynamic
    let version = "Version: 1.0.0 (1)"

    var processor: MockProcessor<AboutState, AboutAction, AboutEffect>!
    var subject: AboutView!

    // MARK: Setup & Teardown

    override func setUp() {
        super.setUp()

        processor = MockProcessor(state: AboutState(copyrightText: copyrightText, version: version))
        let store = Store(processor: processor)

        subject = AboutView(store: store)
    }

    override func tearDown() {
        super.tearDown()

        processor = nil
        subject = nil
    }

    // MARK: Tests

    /// The About header identifies the product and publisher without presenting Bitwarden as either.
    @MainActor
    func test_brandHeader() throws {
        _ = try subject.inspect().find(text: AboutState.productName)
        _ = try subject.inspect().find(text: AboutState.publisherName)
    }

    /// Tapping the help center button dispatches the `.helpCenterTapped` action.
    @MainActor
    func test_helpCenterButton_tap() throws {
        let button = try subject.inspect().find(
            button: AboutState.upstreamLinkTitle(Localizations.bitwardenHelpCenter),
        )
        try button.tap()
        XCTAssertEqual(processor.dispatchedActions.last, .helpCenterTapped)
    }

    /// The flight recorder toggle turns logging on and off.
    @MainActor
    func test_flightRecorder_toggle_tap() async throws {
        let toggle = try subject.inspect().find(toggleWithAccessibilityLabel: Localizations.flightRecorder)

        try toggle.tap()
        try await waitForAsync { !self.processor.effects.isEmpty }
        XCTAssertEqual(processor.effects, [.flightRecorder(.toggleFlightRecorder(true))])
        processor.effects.removeAll()

        processor.state.flightRecorderState.activeLog = FlightRecorderData.LogMetadata(
            duration: .eightHours,
            startDate: .now,
        )
        try toggle.tap()
        try await waitForAsync { !self.processor.effects.isEmpty }
        XCTAssertEqual(processor.effects, [.flightRecorder(.toggleFlightRecorder(false))])
    }

    /// Tapping the flight recorder view recorded logs button dispatches the
    /// `.viewFlightRecorderLogsTapped` action.
    @MainActor
    func test_flightRecorder_viewRecordedLogsButton_tap() throws {
        let button = try subject.inspect().find(button: Localizations.viewRecordedLogs)
        try button.tap()
        XCTAssertEqual(processor.dispatchedActions.last, .flightRecorder(.viewLogsTapped))
    }

    /// Tapping the F.R.I.D.A.Y. source button dispatches the `.fridaySourceTapped` action.
    @MainActor
    func test_fridaySourceButton_tap() throws {
        let button = try subject.inspect().find(button: AboutState.fridaySourceTitle)
        try button.tap()
        XCTAssertEqual(processor.dispatchedActions.last, .fridaySourceTapped)
    }

    /// Tapping the learn about organizations button dispatches the `.learnAboutOrganizationsTapped` action.
    @MainActor
    func test_learnAboutOrganizationsButton_tap() throws {
        let button = try subject.inspect().find(
            button: AboutState.upstreamLinkTitle(Localizations.learnOrg),
        )
        try button.tap()
        XCTAssertEqual(processor.dispatchedActions.last, .learnAboutOrganizationsTapped)
    }

    /// The upstream Bitwarden privacy policy is not presented as PB Media's privacy policy.
    @MainActor
    func test_privacyPolicyButton_notShown() throws {
        XCTAssertThrowsError(try subject.inspect().find(button: Localizations.privacyPolicy))
    }

    /// Tapping the upstream source button dispatches the `.upstreamSourceTapped` action.
    @MainActor
    func test_upstreamSourceButton_tap() throws {
        let button = try subject.inspect().find(button: AboutState.upstreamSourceTitle)
        try button.tap()
        XCTAssertEqual(processor.dispatchedActions.last, .upstreamSourceTapped)
    }

    /// Tapping the version button performs the `.copyVersionInfo` effect.
    @MainActor
    func test_versionButton_tap() async throws {
        let button = try subject.inspect().find(button: version)
        try button.tap()
        try await waitForAsync { !self.processor.effects.isEmpty }
        XCTAssertEqual(processor.effects.last, .copyVersionInfo)
    }

    /// Tapping the web vault button dispatches the `.webVaultTapped` action.
    @MainActor
    func test_webVaultButton_tap() throws {
        let button = try subject.inspect().find(button: AboutState.webVaultTitle)
        try button.tap()
        XCTAssertEqual(processor.dispatchedActions.last, .webVaultTapped)
    }
}
