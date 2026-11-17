import Foundation

/// App configuration.
///
/// Values come from build settings (`Config/Sonder.xcconfig`, plus the git-ignored
/// `Config/Secrets.xcconfig`) which are baked into Info.plist at build time. In debug builds,
/// environment variables of the same name override them, which is handy for pointing a
/// simulator run at a local Supabase stack.
enum Config {
    /// Supabase project URL.
    static var supabaseURL: URL? {
        let raw = value(env: "SUPABASE_URL", plist: "SonderSupabaseURL")
        guard !raw.isEmpty, let url = URL(string: raw), url.host != nil else { return nil }
        return url
    }

    /// Supabase anon/publishable key. Public by design: row-level security protects the data.
    /// Never ship the service-role key in the app.
    static var supabaseAnonKey: String {
        value(env: "SUPABASE_ANON_KEY", plist: "SonderSupabaseAnonKey")
    }

    /// Anthropic API key. When empty, Sonder writes summaries and profiles on-device instead.
    static var anthropicAPIKey: String {
        value(env: "ANTHROPIC_API_KEY", plist: "SonderAnthropicAPIKey")
    }

    /// Claude model used for city summaries and travel profiles.
    static var claudeModel: String {
        let configured = value(env: "CLAUDE_MODEL", plist: "SonderClaudeModel")
        return configured.isEmpty ? "claude-sonnet-5-5" : configured
    }

    static var isAIEnabled: Bool { !anthropicAPIKey.isEmpty }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// Debug-only demo mode: runs fully in memory with sample data and no network backend.
    /// Launch with the `-SonderDemoMode YES` argument (or `SONDER_DEMO_MODE=1`).
    static var isDemoMode: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "SonderDemoMode") { return true }
        return ProcessInfo.processInfo.environment["SONDER_DEMO_MODE"] == "1"
        #else
        return false
        #endif
    }

    private static func value(env: String, plist: String) -> String {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment[env]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        #endif
        let raw = (Bundle.main.object(forInfoDictionaryKey: plist) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // An unresolved build setting shows up literally as "$(NAME)".
        return raw.contains("$(") ? "" : raw
    }
}
