import XCTest

@testable import BitwardenKit

class OSLogErrorReporterTests: BitwardenTestCase {
    // MARK: Tests

    /// `log(error:)` doesn't write errors that are explicitly marked as non-loggable.
    func test_log_nonLoggableError() {
        let logger = CapturingBitwardenLogger()
        let subject = OSLogErrorReporter()
        subject.add(logger: logger)

        subject.log(error: TestNonLoggableError())

        XCTAssertTrue(logger.logs.isEmpty)
    }

    /// `log(error:)` doesn't write errors when local diagnostics are disabled.
    func test_log_whenDisabled() {
        let logger = CapturingBitwardenLogger()
        let subject = OSLogErrorReporter()
        subject.add(logger: logger)
        subject.isEnabled = false

        subject.log(error: NSError(domain: "TestError", code: 1))

        XCTAssertTrue(logger.logs.isEmpty)
    }
}

private struct TestNonLoggableError: NonLoggableError {}

private final class CapturingBitwardenLogger: BitwardenLogger {
    var logs = [String]()

    func log(_ message: String, file: String, line: UInt) {
        logs.append(message)
    }
}
