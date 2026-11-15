//  WHAT: One body asked of the host's model: the Swift that goes inside something this package writes (a work
//        function, a view's body). The answer is decoded, checked against the rules, put in its file and parsed
//        with the toolchain; what was wrong goes back to the model, up to the call's rounds.
//  PIN:  THE SCHEMA IS ADVICE. A host pastes it into the prompt; the answer is decoded and checked here, every round.
//  PIN:  NARROW ASKS. A body, never a file: the package writes the declaration, the imports and the wiring, so the
//        model only says what is the app's own.

import Foundation
import GraniteAgents

struct BodyAsk: Sendable {
    let model: any AgentHostModel
    let rounds: Int
    let note: @Sendable (String) -> Void

    private struct Answer: Decodable { let body: String }

    static let schema = Data(#"{"type":"object","required":["body"],"properties":{"body":{"type":"string","description":"the Swift, as plain text"}}}"#.utf8)

    /// Asks for `what`'s body. `file` puts a body in the file it lands in; `check` names what breaks the rules.
    /// Answers the body and the round it came right in.
    func ask(_ what: String, system: String, user: String, maxTokens: Int = 1_600, seconds: Double = 150,
             file: (String) -> String, check: (String) -> [String]) async throws -> (body: String, rounds: Int) {
        var prompt = user
        var last = "no answer"
        for round in 1...max(1, rounds) {
            var problems: [String] = []
            var body = ""
            do {
                let data = try await model.object(schema: Self.schema, system: system, user: prompt, maxTokens: maxTokens, seconds: seconds)
                if let answer = try? JSONDecoder().decode(Answer.self, from: data) {
                    body = Self.cleaned(answer.body)
                    problems = Self.rules(body) + check(body)
                    if problems.isEmpty, let failure = Self.parse(file(body)) { problems.append("it does not parse: \(failure)") }
                } else {
                    problems.append("the answer was not one JSON object {\"body\": \"…\"}")
                }
            } catch {
                problems.append("\(error)")
            }
            if problems.isEmpty { return (body, round) }
            last = problems.joined(separator: "; ")
            note("\(what): round \(round), \(problems[0].prefix(90))")
            prompt = user + "\n\nYour last answer was:\n" + body + "\n\nWhat was wrong with it:\n"
                + problems.map { "- " + $0 }.joined(separator: "\n") + "\n\nWrite the body again, fixed."
        }
        throw GraniteError.unanswered(["\(what) did not come out right in \(max(1, rounds)) round\(rounds == 1 ? "" : "s"): \(last)"])
    }

    /// The rules every body keeps, whatever it is for.
    static func rules(_ body: String) -> [String] {
        var problems: [String] = []
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append("the body is empty") }
        for word in ["fatalError(", "TODO", "FIXME", "#warning", "preconditionFailure(", "<#"] where body.contains(word) {
            problems.append("it has `\(word)`: write the real thing")
        }
        if body.contains("print(") { problems.append("it prints: report through the app's state instead") }
        return problems
    }

    /// The body as the model meant it: code fences and a repeated declaration taken away.
    static func cleaned(_ text: String) -> String {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            body = body.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if let fence = body.range(of: "```", options: .backwards) { body = String(body[..<fence.lowerBound]) }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for opening in ["var body: some View {", "static func work(", "func work("] where body.hasPrefix(opening) {
            if let open = body.firstIndex(of: "{"), let close = body.lastIndex(of: "}"), open < close {
                body = String(body[body.index(after: open)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return Self.dedented(body)
    }

    /// `text` with the indentation every line shares taken away.
    static func dedented(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let shared = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { $0.prefix { $0 == " " }.count }.min() ?? 0
        return lines.map { $0.count >= shared ? String($0.dropFirst(shared)) : $0 }.joined(separator: "\n")
    }

    /// The parser's complaint about `source`, each error with the line it points at, or nil when it parses.
    static func parse(_ source: String) -> String? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("granite-body-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Body.swift")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(source.utf8).write(to: file)
            guard let failure = try SwiftParse.check([file])?.replacingOccurrences(of: file.path, with: "Body.swift") else { return nil }
            return quoted(failure, in: source)
        } catch {
            return nil
        }
    }

    /// Each `Body.swift:<line>:<column>: error:` line of `failure`, followed by the line of `source` it points at.
    ///
    /// PIN: THE MODEL NEVER SAW THE FILE (Seer R3, 2026-11-15). The body is put inside a file the package writes, so
    /// "Body.swift:46:18" names a line the model cannot count to. Told only that, it wrote the same body three rounds
    /// running (`Button { … } { … }`, byte for byte, at its low temperature) and the page was refused. The line itself
    /// is what it can find in its answer.
    static func quoted(_ failure: String, in source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        return failure.components(separatedBy: "\n").map { row in
            let parts = row.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            guard row.hasPrefix("Body.swift:"), parts.count == 4, let number = Int(parts[1]), (1...lines.count).contains(number) else { return row }
            let code = lines[number - 1].trimmingCharacters(in: .whitespaces)
            return code.isEmpty ? row : row + " — at the line `\(code)`"
        }.joined(separator: "\n")
    }

    /// `text` indented by `spaces` on every line that has something on it.
    static func indented(_ text: String, by spaces: Int) -> String {
        let pad = String(repeating: " ", count: spaces)
        return text.components(separatedBy: "\n").map { $0.isEmpty ? $0 : pad + $0 }.joined(separator: "\n")
    }
}
