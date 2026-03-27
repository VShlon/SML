//
//  RoleState.swift
//  sml
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - Хранит текущую роль пользователя для app-меню.
//  - Обновляет роль через bridge из WebView и через network-refresh.
//  - Устойчиво парсит разные форматы ответа.
//  - Сохраняет последнюю валидную роль, чтобы меню не сбрасывалось из-за временной ошибки.
//

import Foundation

@MainActor
final class RoleState: ObservableObject {

    static let shared = RoleState()

    enum Mode: String {
        case guest
        case client
        case worker
        case accountant
        case administrator
        case manager
        case owner
    }

    @Published private(set) var mode: Mode
    @Published private(set) var wpRole: String
    @Published private(set) var lastError: String?

    private let whoamiURL = AppConfig.whoamiURL
    private let storedRoleKey = "sml_last_role"

    private var isLoading = false
    private var lastRefreshAt: TimeInterval = 0
    private let minRefreshInterval: TimeInterval = 0.6

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 12
        return URLSession(configuration: cfg)
    }()

    private init() {
        let stored = UserDefaults.standard.string(forKey: storedRoleKey) ?? "guest"
        let normalized = Self.normalizeRoleString(stored) ?? "guest"

        self.mode = Self.mode(for: normalized) ?? .guest
        self.wpRole = normalized
        self.lastError = nil
    }

    func setRoleFromBridge(role raw: String?) {
        lastError = nil

        guard let normalized = Self.normalizeRoleString(raw) else {
            return
        }

        if normalized == "guest", mode != .guest {
            return
        }

        applyResolvedRole(normalized)
    }

    func setRoleFromBridge(payload: Any?) {
        lastError = nil

        let source = Self.extractBridgeSource(from: payload)

        if let resolved = Self.extractRole(from: payload) {
            if resolved == "guest", !shouldAcceptGuestTransition(from: source) {
                return
            }

            applyResolvedRole(resolved)
            return
        }

        if Self.payloadExplicitlyRepresentsGuest(payload), shouldAcceptGuestTransition(from: source) {
            applyResolvedRole("guest")
        }
    }

    func refresh() {
        let now = Date().timeIntervalSince1970
        if now - lastRefreshAt < minRefreshInterval { return }
        lastRefreshAt = now

        if isLoading { return }
        isLoading = true
        lastError = nil

        var req = URLRequest(url: whoamiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        req.httpMethod = "GET"
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.httpShouldHandleCookies = true

        Task {
            defer { self.isLoading = false }

            do {
                let (data, resp) = try await session.data(for: req)

                if let http = resp as? HTTPURLResponse {
                    if http.statusCode == 401 || http.statusCode == 403 {
                        self.applyResolvedRole("guest")
                        return
                    }

                    if !(200...299).contains(http.statusCode) {
                        self.lastError = "whoami HTTP \(http.statusCode)"
                        return
                    }
                }

                let obj = try JSONSerialization.jsonObject(with: data, options: [])

                if let resolved = Self.extractRole(from: obj) {
                    self.applyResolvedRole(resolved)
                    return
                }

                if Self.payloadExplicitlyRepresentsGuest(obj) {
                    self.applyResolvedRole("guest")
                    return
                }

                self.lastError = "whoami role not found"

            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    private func applyResolvedRole(_ raw: String) {
        let normalized = Self.normalizeRoleString(raw) ?? "guest"
        wpRole = normalized
        mode = Self.mode(for: normalized) ?? .guest
        UserDefaults.standard.set(normalized, forKey: storedRoleKey)
    }

    private static func mode(for raw: String) -> Mode? {
        switch raw {
        case "administrator", "admin":
            return .administrator
        case "owner", "boss":
            return .owner
        case "manager":
            return .manager
        case "accountant", "bookkeeper", "accounting":
            return .accountant
        case "worker", "employee", "staff":
            return .worker
        case "commercial", "residential", "client", "customer":
            return .client
        case "guest", "anonymous":
            return .guest
        default:
            return nil
        }
    }

    private static func normalizeRoleString(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let cleaned = raw
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: "{", with: " ")
            .replacingOccurrences(of: "}", with: " ")
            .replacingOccurrences(of: "\"", with: " ")
            .replacingOccurrences(of: "'", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty { return nil }

        let separators = CharacterSet(charactersIn: ",|/;: ()-_")
        let candidates = cleaned
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let priority = [
            "administrator", "admin",
            "owner", "boss",
            "manager",
            "accountant", "bookkeeper", "accounting",
            "worker", "employee", "staff",
            "commercial", "residential", "client", "customer",
            "guest", "anonymous"
        ]

        for item in priority where candidates.contains(item) {
            return item
        }

        if let direct = mode(for: cleaned) {
            return direct.rawValue
        }

        return nil
    }

    private enum BridgeSource {
        case unknown
        case dom
        case whoami
    }

    private func shouldAcceptGuestTransition(from source: BridgeSource) -> Bool {
        if mode == .guest {
            return true
        }

        switch source {
        case .whoami:
            return true
        case .dom, .unknown:
            return false
        }
    }

    private static func extractBridgeSource(from payload: Any?) -> BridgeSource {
        if let dict = payload as? [String: Any] {
            if let raw = dict["role_source"] as? String {
                return parseBridgeSource(raw)
            }

            if let raw = dict["source"] as? String {
                return parseBridgeSource(raw)
            }

            return .unknown
        }

        if let dict = payload as? NSDictionary {
            if let raw = dict["role_source"] as? String {
                return parseBridgeSource(raw)
            }

            if let raw = dict["source"] as? String {
                return parseBridgeSource(raw)
            }
        }

        return .unknown
    }

    private static func parseBridgeSource(_ raw: String) -> BridgeSource {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "dom":
            return .dom
        case "whoami":
            return .whoami
        default:
            return .unknown
        }
    }

    private static func extractRole(from payload: Any?) -> String? {
        switch payload {
        case let string as String:
            return normalizeRoleString(string)

        case let array as [Any]:
            for item in array {
                if let resolved = extractRole(from: item) {
                    return resolved
                }
            }
            return nil

        case let dict as [String: Any]:
            let directKeys = [
                "role", "primary_role", "wp_role", "user_role", "current_role", "slug",
                "role_label", "role_text", "roleLabel", "roleText", "userRole", "primaryRole",
                "body_class", "bodyClass", "className"
            ]

            for key in directKeys {
                if let resolved = extractRole(from: dict[key]) {
                    return resolved
                }
            }

            if let resolved = extractRole(from: dict["roles"]) {
                return resolved
            }

            if let resolved = extractRole(from: dict["role_candidates"]) {
                return resolved
            }

            let nestedKeys = ["user", "data", "result", "whoami", "account", "meta"]
            for key in nestedKeys {
                if let resolved = extractRole(from: dict[key]) {
                    return resolved
                }
            }

            return nil

        case let nsDict as NSDictionary:
            var swiftDict: [String: Any] = [:]
            nsDict.forEach { key, value in
                if let stringKey = key as? String {
                    swiftDict[stringKey] = value
                }
            }
            return extractRole(from: swiftDict)

        default:
            return nil
        }
    }

    private static func payloadExplicitlyRepresentsGuest(_ payload: Any?) -> Bool {
        if let dict = payload as? [String: Any] {
            let boolKeys = [
                "logged_in", "is_logged_in", "authenticated", "is_authenticated",
                "loggedIn", "isLoggedIn", "authenticatedUser"
            ]

            for key in boolKeys {
                if let flag = dict[key] as? Bool, flag == false {
                    return true
                }
            }

            if let role = dict["role"] as? String, role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let loggedIn = dict["loggedIn"] as? Bool, loggedIn {
                    return false
                }
                return true
            }

            let nestedKeys = ["user", "data", "result", "whoami", "account", "meta"]
            for key in nestedKeys where payloadExplicitlyRepresentsGuest(dict[key]) {
                return true
            }
        }

        if let dict = payload as? NSDictionary {
            let boolKeys = [
                "logged_in", "is_logged_in", "authenticated", "is_authenticated",
                "loggedIn", "isLoggedIn", "authenticatedUser"
            ]

            for key in boolKeys {
                if let flag = dict[key] as? Bool, flag == false {
                    return true
                }
            }

            if let role = dict["role"] as? String, role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let loggedIn = dict["loggedIn"] as? Bool, loggedIn {
                    return false
                }
                return true
            }

            let nestedKeys = ["user", "data", "result", "whoami", "account", "meta"]
            for key in nestedKeys where payloadExplicitlyRepresentsGuest(dict[key]) {
                return true
            }
        }

        if let string = payload as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.isEmpty || trimmed == "guest" || trimmed == "anonymous"
        }

        if let number = payload as? NSNumber {
            return number.boolValue == false
        }

        return false
    }
}
