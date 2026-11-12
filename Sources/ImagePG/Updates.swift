import AppKit

/// A published GitHub release.
struct ReleaseInfo {
    let version: String
    let name: String
    let url: URL
}

/// Asks GitHub for the latest release and compares it with the running version.
/// Only the public releases API is contacted; nothing about the user is sent.
enum UpdateChecker {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/html-koder-com/imagepg/releases/latest")!
    private static let checksAtLaunchKey = "CheckForUpdatesAtLaunch"
    private static let skippedVersionKey = "SkippedUpdateVersion"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var checksAtLaunch: Bool {
        get { UserDefaults.standard.object(forKey: checksAtLaunchKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: checksAtLaunchKey) }
    }

    static var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: skippedVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: skippedVersionKey) }
    }

    /// Numeric components of "v1.2.3", "1.2" or "1.2.3-beta" → [1, 2, 3].
    static func components(_ version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        let core = trimmed.drop { $0 == "v" || $0 == "V" }.prefix { $0.isNumber || $0 == "." }
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = components(candidate), b = components(installed)
        guard !a.isEmpty else { return false }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true else { return nil }
        let version = String(tag.drop { $0 == "v" || $0 == "V" })
        let name = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "ImagePG \(version)"
        return ReleaseInfo(version: version, name: name, url: page)
    }

    /// Calls back on the main queue with the latest release, or nil when it cannot be determined.
    static func fetchLatest(_ completion: @escaping (ReleaseInfo?) -> Void) {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ImagePG/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let release = ok ? data.flatMap(parse) : nil
            DispatchQueue.main.async { completion(release) }
        }.resume()
    }
}
