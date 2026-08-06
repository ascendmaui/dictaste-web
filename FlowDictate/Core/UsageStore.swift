import Foundation
import UserNotifications

/// Tracks managed AI polish usage for free-tier caps and soft notifications.
@MainActor
@Observable
final class UsageStore {
    static let shared = UsageStore()

    var wordsUsed: Int = 0
    var wordsLimit: Int? = 2_000
    var plan: String = "free"
    var period: String = ""
    var lastError: String?
    var quotaExceeded: Bool = false
    var lastFetched: Date?

    private static let usedKey = "usageWordsUsed"
    private static let limitKey = "usageWordsLimit"
    private static let planKey = "usagePlan"
    private static let periodKey = "usagePeriod"
    private static let warned80Key = "usageWarned80"
    private static let warned100Key = "usageWarned100"

    private init() {
        wordsUsed = UserDefaults.standard.integer(forKey: Self.usedKey)
        let lim = UserDefaults.standard.object(forKey: Self.limitKey) as? Int
        wordsLimit = lim
        plan = UserDefaults.standard.string(forKey: Self.planKey) ?? "free"
        period = UserDefaults.standard.string(forKey: Self.periodKey) ?? ""
    }

    var fraction: Double {
        guard let limit = wordsLimit, limit > 0 else { return 0 }
        return min(1, Double(wordsUsed) / Double(limit))
    }

    var remaining: Int? {
        guard let limit = wordsLimit else { return nil }
        return max(0, limit - wordsUsed)
    }

    var meterLabel: String {
        if plan == "dev" {
            return "Developer · unlimited BYO"
        }
        if let limit = wordsLimit {
            return "\(wordsUsed) / \(limit) words"
        }
        return "Unlimited"
    }

    var isNearLimit: Bool { fraction >= 0.8 && fraction < 1 }
    var isAtLimit: Bool {
        if quotaExceeded { return true }
        guard let limit = wordsLimit else { return false }
        return wordsUsed >= limit
    }

    func apply(wordsUsed: Int, wordsLimit: Int?, plan: String?, period: String?) {
        let periodChanged = (period ?? "") != self.period && !(period ?? "").isEmpty
        self.wordsUsed = wordsUsed
        self.wordsLimit = wordsLimit
        if let plan { self.plan = plan }
        if let period, !period.isEmpty { self.period = period }
        if periodChanged {
            UserDefaults.standard.removeObject(forKey: Self.warned80Key)
            UserDefaults.standard.removeObject(forKey: Self.warned100Key)
            quotaExceeded = false
        }
        persist()
        maybeNotify()
    }

    func markQuotaExceeded() {
        quotaExceeded = true
        if let limit = wordsLimit {
            wordsUsed = max(wordsUsed, limit)
        }
        persist()
        notifyOnce(key: Self.warned100Key, title: "Daily AI polish limit reached",
                   body: "You've used your free 2,000 words today. Upgrade to Pro for a larger monthly pool — or keep dictating without polish.")
    }

    func refreshFromServer() async {
        let key = CloudPolisher.licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        var request = URLRequest(url: CloudPolisher.apiBaseURL.appendingPathComponent("api/v1/me"))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            let used = json["wordsUsed"] as? Int ?? 0
            let limit = json["wordsLimit"] as? Int
            let plan = json["plan"] as? String
            let period = json["usagePeriod"] as? String
            apply(wordsUsed: used, wordsLimit: limit, plan: plan, period: period)
            lastFetched = .now
            lastError = nil
            quotaExceeded = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persist() {
        UserDefaults.standard.set(wordsUsed, forKey: Self.usedKey)
        if let wordsLimit {
            UserDefaults.standard.set(wordsLimit, forKey: Self.limitKey)
        }
        UserDefaults.standard.set(plan, forKey: Self.planKey)
        UserDefaults.standard.set(period, forKey: Self.periodKey)
    }

    private func maybeNotify() {
        if isAtLimit {
            notifyOnce(key: Self.warned100Key, title: "AI polish limit reached",
                       body: "Free tier is capped at 2,000 words/day. Upgrade to Pro to keep polishing.")
        } else if isNearLimit {
            notifyOnce(key: Self.warned80Key, title: "Approaching free polish limit",
                       body: "You've used \(Int(fraction * 100))% of today's free AI polish words.")
        }
    }

    private func notifyOnce(key: String, title: String, body: String) {
        if UserDefaults.standard.bool(forKey: key) { return }
        UserDefaults.standard.set(true, forKey: key)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let req = UNNotificationRequest(
                identifier: key + UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(req)
        }
    }
}
