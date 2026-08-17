// Template. Copy to `Secrets.swift` (gitignored, and the only file the build
// compiles) and fill in your own values:
//
//     cp YourChat/Config/Secrets.example.swift YourChat/Config/Secrets.swift
//
// Never commit a real token. Release builds must use wss://, not ws://.

import Foundation

enum Secrets {
    /// Local development. On a real iPhone, 127.0.0.1 is the phone itself —
    /// point this at the wss:// entry point instead.
    static let relayHost = "127.0.0.1:9191"

    /// Plain ws/http is only acceptable against localhost during development.
    static let useTLS = false

    /// Must equal YOURCHAT_TOKEN in relay/.env.
    /// Generate with: openssl rand -hex 32
    static let appToken = "replace-with-the-relay-token"
}
