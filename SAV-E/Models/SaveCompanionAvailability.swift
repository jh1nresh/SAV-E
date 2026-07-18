enum SaveCompanionAvailability {
    // Only internal Debug builds explicitly opt in while companion art is provisional.
#if SAVE_INTERNAL_COMPANIONS
    static let isEnabled = true
#else
    static let isEnabled = false
#endif
}
