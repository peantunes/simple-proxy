//
//  ProxyRule.swift
//  SimpleProxy
//
//  Created by Pedro Antunes on 28/04/2025.
//

import Foundation

struct ProxyRule {
    let pattern: String  // e.g., "/api/v1/list*"
    let localFilePath: String  // path to local file to serve
}

class RulesManager {
    static let shared = RulesManager()

    private(set) var rules: [ProxyRule] = []

    private init() {
        loadRules()
    }

    func loadRules() {
        rules.removeAll()

        let mocksFolder = "/path/to/Mocks" // TODO: Adjust your folder path

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: mocksFolder) else {
            print("Failed to read mocks folder.")
            return
        }

        for entry in contents {
            let fullPath = mocksFolder + "/" + entry
            if entry.hasSuffix(".json") {
                let pattern = "/" + entry.replacingOccurrences(of: ".json", with: "*")
                rules.append(ProxyRule(pattern: pattern, localFilePath: fullPath))
            } else {
                let pattern = "/" + entry + "/*"
                rules.append(ProxyRule(pattern: pattern, localFilePath: fullPath + "/"))
            }
        }

        print("Loaded \(rules.count) rules.")
    }

    func matchedRule(for url: String) -> ProxyRule? {
        for rule in rules {
            if wildcardMatch(input: url, pattern: rule.pattern) {
                return rule
            }
        }
        return nil
    }

    private func wildcardMatch(input: String, pattern: String) -> Bool {
        let regex = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        return input.range(of: "^" + regex + "$", options: .regularExpression) != nil
    }
}
