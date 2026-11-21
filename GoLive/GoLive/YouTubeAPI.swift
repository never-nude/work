import Foundation

/// The handful of YouTube Live Streaming API calls the app needs.
struct YouTubeAPI {
    struct Ingest {
        let streamID: String
        let url: String
        let key: String
    }

    struct APIError: LocalizedError {
        let status: Int
        let reason: String
        let message: String
        var errorDescription: String? {
            switch reason {
            case "liveStreamingNotEnabled":
                return "Live streaming isn't enabled on this channel yet. Turn it on at youtube.com/features (first activation takes up to 24 hours)."
            case "quotaExceeded", "dailyLimitExceeded":
                return "YouTube API quota is used up for today."
            case "userRequestsExceedRateLimit", "livePermissionBlocked":
                return "YouTube is blocking new live streams on this channel right now: \(message)"
            case "accessNotConfigured":
                return "The YouTube Data API v3 isn't enabled in your Google Cloud project."
            default:
                return message.isEmpty ? "YouTube error \(status)" : message
            }
        }
    }

    let token: String
    private static let base = "https://www.googleapis.com/youtube/v3/"

    @discardableResult
    private func call(_ method: String, _ path: String, query: [String: String], body: [String: Any]? = nil) async throws -> [String: Any] {
        var components = URLComponents(string: Self.base + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let error = json["error"] as? [String: Any]
            let first = (error?["errors"] as? [[String: Any]])?.first
            diag("YouTube \(method) \(path) -> HTTP \(status) \(first?["reason"] as? String ?? "") \((error?["message"] as? String ?? "").prefix(160))")
            throw APIError(
                status: status,
                reason: first?["reason"] as? String ?? "",
                message: (error?["message"] as? String ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            )
        }
        return json
    }

    func channelTitle() async throws -> String {
        let json = try await call("GET", "channels", query: ["part": "snippet", "mine": "true"])
        let item = (json["items"] as? [[String: Any]])?.first
        guard let title = (item?["snippet"] as? [String: Any])?["title"] as? String else {
            throw AppError("This Google account has no YouTube channel.")
        }
        return title
    }

    /// Creates the reusable RTMP ingest point the phone publishes to.
    func createStream() async throws -> Ingest {
        let json = try await call("POST", "liveStreams", query: ["part": "snippet,cdn,contentDetails"], body: [
            "snippet": ["title": "GoLive iPhone"],
            "cdn": ["ingestionType": "rtmp", "resolution": "variable", "frameRate": "variable"],
            "contentDetails": ["isReusable": true]
        ])
        let info = (json["cdn"] as? [String: Any])?["ingestionInfo"] as? [String: Any]
        guard let id = json["id"] as? String,
              let key = info?["streamName"] as? String,
              let url = (info?["rtmpsIngestionAddress"] as? String) ?? (info?["ingestionAddress"] as? String) else {
            throw AppError("YouTube didn't return an ingest address.")
        }
        return Ingest(streamID: id, url: url, key: key)
    }

    /// Creates a broadcast that goes live by itself as soon as video arrives.
    func createBroadcast(title: String, privacy: Privacy) async throws -> String {
        let json = try await call("POST", "liveBroadcasts", query: ["part": "snippet,status,contentDetails"], body: [
            "snippet": [
                "title": title,
                "scheduledStartTime": ISO8601DateFormatter().string(from: Date())
            ],
            "status": [
                "privacyStatus": privacy.rawValue,
                "selfDeclaredMadeForKids": false
            ],
            "contentDetails": [
                "enableAutoStart": true,
                "enableAutoStop": true,
                "enableDvr": true,
                "latencyPreference": "low",
                "monitorStream": ["enableMonitorStream": false]
            ]
        ])
        guard let id = json["id"] as? String else { throw AppError("YouTube didn't return a broadcast ID.") }
        return id
    }

    func bind(broadcastID: String, streamID: String) async throws {
        try await call("POST", "liveBroadcasts/bind", query: ["id": broadcastID, "streamId": streamID, "part": "id"])
    }

    /// "ready", "testing", "live", "complete", ... or nil if the broadcast is gone.
    func lifeCycleStatus(broadcastID: String) async throws -> String? {
        let json = try await call("GET", "liveBroadcasts", query: ["part": "status", "id": broadcastID])
        let item = (json["items"] as? [[String: Any]])?.first
        return (item?["status"] as? [String: Any])?["lifeCycleStatus"] as? String
    }

    /// What YouTube's ingest sees: streamStatus ("active" means data is arriving) and
    /// healthStatus ("good", "ok", "bad", "noData").
    func streamHealth(streamID: String) async throws -> (stream: String, health: String) {
        let json = try await call("GET", "liveStreams", query: ["part": "status", "id": streamID])
        let item = (json["items"] as? [[String: Any]])?.first
        let status = item?["status"] as? [String: Any]
        let stream = status?["streamStatus"] as? String ?? "missing"
        let health = (status?["healthStatus"] as? [String: Any])?["status"] as? String ?? "unknown"
        return (stream, health)
    }

    func transition(broadcastID: String, to status: String) async throws {
        try await call("POST", "liveBroadcasts/transition", query: ["broadcastStatus": status, "id": broadcastID, "part": "status"])
    }

    func deleteBroadcast(_ broadcastID: String) async throws {
        try await call("DELETE", "liveBroadcasts", query: ["id": broadcastID])
    }
}
