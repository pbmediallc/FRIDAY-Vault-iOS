import BitwardenKit
import BitwardenShared

/// A factory to create `ErrorReporter` instances.
enum ErrorReporterFactory {
    // MARK: Static Functions

    /// Creates the local-only default error reporter.
    static func makeDefaultErrorReporter() -> ErrorReporter {
        OSLogErrorReporter()
    }
}
