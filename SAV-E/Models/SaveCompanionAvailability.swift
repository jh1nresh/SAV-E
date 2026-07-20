import Foundation

enum SaveCompanionAvailability {
    static let optInArgument = "--enable-internal-companions"

#if SAVE_INTERNAL_COMPANIONS
    private static let internalBuild = true
#else
    private static let internalBuild = false
#endif

    // Companion art stays provisional. Internal builds must still opt in at
    // launch so normal Debug, reviewer-demo, and screenshot flows match Release.
    static let isEnabled = shouldEnable(
        arguments: ProcessInfo.processInfo.arguments,
        internalBuild: internalBuild
    )

    static func shouldEnable(arguments: [String], internalBuild: Bool) -> Bool {
        internalBuild && arguments.contains(optInArgument)
    }
}
