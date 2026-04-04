import Foundation
import os.log

private let log = Logger(subsystem: "com.notchbar", category: "update")

class UpdateChecker {
    static let shared = UpdateChecker()
    static let currentVersion = "0.1.0"
    private let repoOwner = "lukataylo"
    private let repoName = "NotchBar"

    private var timer: Timer?

    func startChecking() {
        checkForUpdate()
        timer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            self?.checkForUpdate()
        }
    }

    func checkForUpdate() {
        log.info("Checking for updates (current: \(Self.currentVersion))")
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("NotchBar/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                log.warning("Update check failed: \(error.localizedDescription)")
                return
            }
            guard let data = data else {
                log.warning("Update check returned no data")
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                log.debug("Update check: could not parse response")
                return
            }

            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            log.info("Latest version: \(latestVersion)")

            if self.isNewer(latestVersion, than: Self.currentVersion) {
                log.info("Update available: \(latestVersion)")
                DispatchQueue.main.async {
                    ClaudeCodeBridge.shared?.sendNotification(
                        title: "NotchBar Update Available",
                        body: "Version \(latestVersion) is available (you have \(Self.currentVersion))"
                    )
                }
            }
        }.resume()
    }

    private func isNewer(_ latest: String, than current: String) -> Bool {
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(l.count, c.count) {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv > cv { return true }
            if lv < cv { return false }
        }
        return false
    }
}
