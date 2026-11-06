import Foundation

/// One line of `/app/n2it/room.php`: who the PBX says is in a conference room right now.
struct RoomMember: Decodable {
    let id: Int
    let match: String?
    let isSelf: Bool
    enum CodingKeys: String, CodingKey { case id, match, isSelf = "self" }
}

struct RoomAnswer: Decodable { let count: Int?; let members: [RoomMember] }

/// The same value as the PBX's `match`: the part before any @, digits only, then the last 9 digits when there are 9 or
/// more, otherwise all of them. So 082..., 2782... and +2782... agree.
func roomMatch(_ number: String) -> String {
    let digits = (number.split(separator: "@", omittingEmptySubsequences: false).first ?? "").filter(\.isNumber)
    return String(digits.suffix(9))
}

/// Works out who left from the PBX's answers only. A card is tied to a member id the first time its match appears; a
/// card with no id yet is never removed (the REFER may still be running, or its number may show differently in the
/// room), so at worst a card stays, as it did before 0.3.7. It must never go while that person can still hear the call.
struct RoomCards {
    /// How many 200 answers in a row a tied id must be missing from before its card goes.
    static let missesToLeave = 2
    private var tied: [String: Int] = [:]
    private var misses: [String: Int] = [:]

    /// Returns the ids of the cards whose person has left.
    mutating func update(cards: [(id: String, number: String)], members: [RoomMember]) -> [String] {
        let others = members.filter { !$0.isSelf }
        for card in cards where tied[card.id] == nil {
            let key = roomMatch(card.number)
            let used = Set(tied.values)
            if let m = others.first(where: { $0.match == key && !used.contains($0.id) }) { tied[card.id] = m.id }
        }
        let present = Set(others.map(\.id))
        var left: [String] = []
        for card in cards {
            guard let id = tied[card.id] else { continue }
            if present.contains(id) { misses[card.id] = 0; continue }
            let n = (misses[card.id] ?? 0) + 1
            misses[card.id] = n
            if n >= Self.missesToLeave { left.append(card.id) }
        }
        return left
    }
}

/// While we are in a *32 room: ask the PBX who is in it every 3 s, one request at a time, and report who left. Only a
/// 200 changes the cards. Same login as contacts.php.
final class RoomTracker {
    /// Seconds until the next request after this HTTP status (0 = no answer at all); nil = stop for this call.
    static func delay(after status: Int) -> TimeInterval? {
        switch status {
        case 400, 401: return nil
        case 429: return 10
        default: return 3
        }
    }

    private let url: URL
    private let login: String
    private let cards: () -> [(id: String, number: String)]
    private let onCount: (Int) -> Void
    private let onLeft: ([String]) -> Void
    private var state = RoomCards()
    private var task: URLSessionDataTask?
    private var timer: DispatchWorkItem?
    private var stopped = false

    /// `room` is the 7 digits dialled after *32. Calls back on the main queue.
    init?(room: String, account acc: Account, cards: @escaping () -> [(id: String, number: String)],
          onCount: @escaping (Int) -> Void, onLeft: @escaping ([String]) -> Void) {
        guard acc.isConfigured, let url = URL(string: "https://\(acc.domain)/app/n2it/room.php?room=\(room)") else { return nil }
        self.url = url
        login = Data("\(acc.user):\(acc.password)".utf8).base64EncodedString()
        self.cards = cards
        self.onCount = onCount
        self.onLeft = onLeft
    }

    func start() { schedule(3) }

    func stop() {
        stopped = true
        timer?.cancel(); timer = nil
        task?.cancel(); task = nil
    }

    private func schedule(_ seconds: TimeInterval) {
        timer = later(seconds) { [weak self] in self?.poll() }
    }

    private func poll() {
        guard !stopped else { return }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Basic \(login)", forHTTPHeaderField: "Authorization")
        task = URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async { self?.answered(status, data) }
        }
        task?.resume()
    }

    private func answered(_ status: Int, _ data: Data?) {
        guard !stopped else { return }
        task = nil
        if status == 200, let data, let answer = try? JSONDecoder().decode(RoomAnswer.self, from: data) {
            if let count = answer.count { onCount(count) }
            let left = state.update(cards: cards(), members: answer.members)
            if !left.isEmpty { onLeft(left) }
        }
        guard !stopped, let next = Self.delay(after: status) else { return }
        schedule(next)
    }
}
