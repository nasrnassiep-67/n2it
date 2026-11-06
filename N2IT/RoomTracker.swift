import Foundation

/// One line of `/app/n2it/room.php`: who the PBX says is in a conference room right now.
struct RoomMember {
    let id: Int
    let number: String
    let match: String?
    let name: String?
    let isSelf: Bool
}

/// Forgiving on purpose, like Android's reader: 12 and "12" are the same id, and fields we don't use can be anything.
struct RoomAnswer {
    let room: String?
    let count: Int?
    /// True for the operator, the phone that pressed Merge: only they can remove people.
    let host: Bool?
    let members: [RoomMember]

    private static func int(_ v: Any?) -> Int? {
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return (v as? NSNumber)?.intValue
    }
    private static func text(_ v: Any?) -> String? { (v as? String) ?? (v as? NSNumber)?.stringValue }
    private static func bool(_ v: Any?) -> Bool? {
        if let s = v as? String { return ["true", "1"].contains(s.lowercased()) }
        return (v as? NSNumber)?.boolValue
    }

    init?(_ data: Data) {
        guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = top["members"] as? [[String: Any]] else { return nil }
        var out: [RoomMember] = []
        for m in list {
            guard let id = Self.int(m["id"]) else { return nil }
            out.append(RoomMember(id: id, number: Self.text(m["number"]) ?? "", match: Self.text(m["match"]),
                                  name: Self.text(m["name"]), isSelf: Self.bool(m["self"]) ?? false))
        }
        room = Self.text(top["room"])
        count = Self.int(top["count"])
        host = Self.bool(top["host"])
        members = out
    }
}

/// The same value as the PBX's `match`: the part before any @, digits only, then the last 9 digits when there are 9 or
/// more, otherwise all of them. So 082..., 2782... and +2782... agree.
func roomMatch(_ number: String) -> String {
    let digits = (number.split(separator: "@", omittingEmptySubsequences: false).first ?? "").filter(\.isNumber)
    return String(digits.suffix(9))
}

/// Works out who left from the PBX's answers only, as Android's RoomTracker. A card is tied to a member id the first
/// time its match appears. A card must never go while that person can still hear the call.
struct RoomCards {
    /// How many 200 answers in a row a tied id must be missing from before its card goes.
    static let missesToLeave = 2
    /// How many 200 answers a card can stay untied (15 s) before it goes quietly: someone else answered that call.
    static let listsToGiveUp = 5
    private var tied: [String: Int] = [:]
    private var misses: [String: Int] = [:]
    private var waiting: [String: Int] = [:]

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

    /// Cards never tied after 5 answers. Pass only cards whose REFER has finished.
    mutating func stale(_ cards: [String]) -> [String] {
        waiting = waiting.filter { cards.contains($0.key) }
        var old: [String] = []
        for card in cards where tied[card] == nil {
            let n = (waiting[card] ?? 0) + 1
            waiting[card] = n
            if n >= Self.listsToGiveUp { old.append(card); waiting[card] = nil }
        }
        return old
    }

    /// Members in the room with no card yet.
    func untied(_ members: [RoomMember]) -> [RoomMember] {
        let used = Set(tied.values)
        return members.filter { !$0.isSelf && !used.contains($0.id) }
    }

    mutating func tie(_ card: String, to member: Int) { tied[card] = member }
    func member(of card: String) -> Int? { tied[card] }
}

/// `/app/n2it/room.php`, same login as contacts.php. Calls back on the main queue.
struct RoomApi {
    private let base: String
    private let login: String

    init?(_ acc: Account) {
        guard acc.isConfigured else { return nil }
        base = "https://\(acc.domain)/app/n2it/room.php"
        login = Data("\(acc.user.trimmingCharacters(in: .whitespaces)):\(acc.password)".utf8).base64EncodedString()
    }

    private func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Basic \(login)", forHTTPHeaderField: "Authorization")
        return req
    }

    /// `room` nil = whichever room this login is in. Status 0 = no answer at all.
    @discardableResult
    func get(room: String?, _ done: @escaping (Int, RoomAnswer?) -> Void) -> URLSessionDataTask? {
        guard let url = URL(string: base + (room.map { "?room=\($0)" } ?? "")) else { return nil }
        let task = URLSession.shared.dataTask(with: request(url)) { data, resp, _ in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let answer = status == 200 ? data.flatMap { RoomAnswer($0) } : nil
            dlog("room \(room ?? "search") \(status): \(String(decoding: (data ?? Data()).prefix(600), as: UTF8.self))")
            DispatchQueue.main.async { done(status, answer) }
        }
        task.resume()
        return task
    }

    /// Operator only. `done(true)` when the PBX removed them.
    func remove(room: String, member: Int, _ done: @escaping (Bool) -> Void) {
        guard let url = URL(string: base) else { done(false); return }
        var req = request(url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("room=\(room)&member=\(member)".utf8)
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            dlog("room remove \(member): \(status)")
            DispatchQueue.main.async { done(status == 200) }
        }.resume()
    }
}

/// While we are in a *32 room: ask the PBX who is in it every 3 s, one request at a time. Only a 200 changes the cards.
final class RoomTracker {
    /// Seconds until the next request after this HTTP status (0 = no answer at all); nil = stop for this call.
    static func delay(after status: Int, normal: TimeInterval = 3) -> TimeInterval? {
        switch status {
        case 400, 401: return nil
        case 429: return 10
        default: return normal
        }
    }
    /// 404s in a row, after a 200, that mean the room closed and the hang-up never reached us.
    static let notFoundToClose = 3

    private let api: RoomApi
    private let room: String
    private let onAnswer: (RoomAnswer) -> Void
    private let onClosed: () -> Void
    private var task: URLSessionDataTask?
    private var timer: DispatchWorkItem?
    private var stopped = false
    private var seen = false
    private var notFound = 0

    /// `room` is the 7 digits dialled after *32.
    init(api: RoomApi, room: String, onAnswer: @escaping (RoomAnswer) -> Void, onClosed: @escaping () -> Void) {
        self.api = api; self.room = room; self.onAnswer = onAnswer; self.onClosed = onClosed
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
        task = api.get(room: room) { [weak self] status, answer in self?.answered(status, answer) }
    }

    private func answered(_ status: Int, _ answer: RoomAnswer?) {
        guard !stopped else { return }
        task = nil
        if let answer { seen = true; notFound = 0; onAnswer(answer) }
        guard !stopped else { return }
        if status == 404 && seen {
            notFound += 1
            if notFound >= Self.notFoundToClose { stop(); onClosed(); return }
        }
        guard let next = Self.delay(after: status) else { return }
        schedule(next)
    }
}
