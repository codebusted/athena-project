import Foundation

public struct LeetCodeProblem: Equatable, Sendable {
    public var frontendId: String
    public var title: String
    public var slug: String
    public var difficulty: String
    /// LeetCode's daily challenges roll over at 00:00 UTC; this is that UTC date.
    public var challengeDate: String

    public var url: URL { URL(string: "https://leetcode.com/problems/\(slug)/")! }
}

/// Isolates the unofficial LeetCode integration. It only reads the public "question of today";
/// it never sends cookies or credentials and never touches the user's LeetCode account.
public struct LeetCodeService: Sendable {
    public static let fallbackURL = URL(string: "https://leetcode.com/problemset/")!
    private static let endpoint = URL(string: "https://leetcode.com/graphql")!
    private static let query = """
        query questionOfToday { activeDailyCodingChallengeQuestion { date link \
        question { questionFrontendId title titleSlug difficulty } } }
        """

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    public func fetchDailyProblem() async throws -> LeetCodeProblem {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://leetcode.com", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "operationName": "questionOfToday", "query": Self.query, "variables": [String: String](),
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> LeetCodeProblem {
        struct Envelope: Decodable {
            struct DataField: Decodable { let activeDailyCodingChallengeQuestion: Daily? }
            struct Daily: Decodable { let date: String; let question: Question }
            struct Question: Decodable {
                let questionFrontendId: String
                let title: String
                let titleSlug: String
                let difficulty: String
            }
            let data: DataField?
        }
        guard let daily = try JSONDecoder().decode(Envelope.self, from: data).data?.activeDailyCodingChallengeQuestion,
              !daily.question.title.isEmpty, !daily.question.titleSlug.isEmpty
        else { throw URLError(.cannotParseResponse) }
        let q = daily.question
        return LeetCodeProblem(
            frontendId: q.questionFrontendId, title: q.title, slug: q.titleSlug, difficulty: q.difficulty,
            challengeDate: daily.date)
    }
}
