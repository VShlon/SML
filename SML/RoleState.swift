//
//  RoleState.swift
//  SML
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - Источник правды для режима меню.
//  - Режимы: guest, client, worker, accountant, admin, owner, menager.
//  - Основной способ: роль приходит из WebView через bridge.
//  - Fallback: URLSession whoami.
//  - Защита: авторизованный пользователь не должен падать в guest от временного сбоя whoami.
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
        case admin
        case owner
        case menager
    }

    @Published private(set) var mode: Mode = .guest
    @Published private(set) var wpRole: String = "guest"
    @Published private(set) var lastError: String? = nil

    private let whoamiURL = URL(string: "https://stmaryslandscaping.ca/wp-json/sml/v1/whoami")!

    private let storedModeKey = "sml.role.mode"
    private let storedRoleKey = "sml.role.wpRole"

    private var isLoading: Bool = false
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
        restorePersistedAuthorizedRoleIfNeeded()
    }

    func setRoleFromBridge(role raw: String?) {
        lastError = nil
        resolveAndApply(from: [
            "role": raw ?? ""
        ])
    }

    func setRoleFromBridge(payload: [String: Any]) {
        lastError = nil
        resolveAndApply(from: payload)
    }

    func refresh() {
        let now = Date().timeIntervalSince1970
        if now - lastRefreshAt < minRefreshInterval {
            return
        }
        lastRefreshAt = now

        if isLoading {
            return
        }

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
                        self.applyGuest(clearPersisted: true)
                        return
                    }

                    if http.statusCode < 200 || http.statusCode >= 300 {
                        self.lastError = "whoami HTTP \(http.statusCode)"
                        self.keepAuthorizedRoleIfPossible()
                        return
                    }
                }

                let obj = try JSONSerialization.jsonObject(with: data, options: [])
                guard let dict = obj as? [String: Any] else {
                    self.lastError = "whoami invalid JSON"
                    self.keepAuthorizedRoleIfPossible()
                    return
                }

                self.resolveAndApply(from: dict)

            } catch {
                self.lastError = error.localizedDescription
                self.keepAuthorizedRoleIfPossible()
            }
        }
    }

    private func resolveAndApply(from payload: [String: Any]) {
        if isExplicitUnauthorized(payload) {
            applyGuest(clearPersisted: true)
            return
        }

        let authenticated = isAuthenticated(payload)
        let candidates = collectCandidates(from: payload)

        if let resolved = firstResolvedRole(from: candidates) {
            applyAuthorized(mode: resolved.mode, wpRole: resolved.rawRole)
            return
        }

        if authenticated {
            if let currentAuthorized = currentAuthorizedMode() {
                applyAuthorized(mode: currentAuthorized, wpRole: wpRoleForMode(currentAuthorized))
                return
            }

            if let persisted = persistedAuthorizedMode() {
                applyAuthorized(mode: persisted, wpRole: wpRoleForMode(persisted))
                return
            }

            if let inferred = inferRoleFromHints(payload: payload) {
                applyAuthorized(mode: inferred, wpRole: wpRoleForMode(inferred))
                return
            }

            applyAuthorized(mode: .client, wpRole: wpRoleForMode(.client))
            return
        }

        if hasAnyAuthHint(payload) {
            keepAuthorizedRoleIfPossible()
            return
        }

        keepAuthorizedRoleIfPossible()
    }

    private func collectCandidates(from payload: [String: Any]) -> [String] {
        var out: [String] = []

        func append(_ value: Any?) {
            if let s = value as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(s)
            }

            if let arr = value as? [String] {
                out.append(contentsOf: arr)
            }

            if let arr = value as? [Any] {
                for item in arr {
                    if let s = item as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        out.append(s)
                    }
                }
            }
        }

        append(payload["role"])
        append(payload["wp_role"])
        append(payload["role_label"])
        append(payload["roles"])
        append(payload["role_candidates"])
        append(payload["current_path"])
        append(payload["href"])
        append(payload["body_class"])

        return out
    }

    private func firstResolvedRole(from candidates: [String]) -> (mode: Mode, rawRole: String)? {
        for candidate in candidates {
            if let resolved = resolveRole(candidate) {
                return resolved
            }
        }
        return nil
    }

    private func resolveRole(_ raw: String) -> (mode: Mode, rawRole: String)? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty {
            return nil
        }

        if containsAny(value, [
            "owner",
            "site_owner",
            "business_owner"
        ]) {
            return (.owner, "owner")
        }

        if containsAny(value, [
            "menager",
            "manager",
            "site_manager",
            "project_manager"
        ]) {
            return (.menager, "menager")
        }

        if containsAny(value, [
            "administrator",
            "admin",
            "wp-admin"
        ]) {
            return (.admin, "admin")
        }

        if containsAny(value, [
            "accountant",
            "bookkeeper",
            "finance",
            "billing",
            "payroll",
            "monthly-billing",
            "payroll-review"
        ]) {
            return (.accountant, "accountant")
        }

        if containsAny(value, [
            "worker",
            "employee",
            "crew",
            "technician",
            "workday",
            "tasks-today",
            "report"
        ]) {
            return (.worker, "worker")
        }

        if containsAny(value, [
            "client",
            "customer",
            "customers",
            "commercial",
            "residential",
            "member",
            "subscriber"
        ]) {
            return (.client, "client")
        }

        if containsAny(value, [
            "guest",
            "anonymous"
        ]) {
            return nil
        }

        return nil
    }

    private func inferRoleFromHints(payload: [String: Any]) -> Mode? {
        let path = extractString(payload["current_path"]).lowercased()
        let href = extractString(payload["href"]).lowercased()
        let bodyClass = extractString(payload["body_class"]).lowercased()
        let joined = [path, href, bodyClass].joined(separator: " ")

        if let resolved = resolveRole(joined) {
            return resolved.mode
        }

        return nil
    }

    private func isExplicitUnauthorized(_ payload: [String: Any]) -> Bool {
        if let status = extractInt(payload["status"]), status == 401 || status == 403 {
            return true
        }

        if let status = extractInt(payload["http_status"]), status == 401 || status == 403 {
            return true
        }

        let role = extractString(payload["role"]).lowercased()
        let authenticated = isAuthenticated(payload)

        if role == "guest" && payload.keys.contains("role") && authenticated == false {
            return true
        }

        return false
    }

    private func isAuthenticated(_ payload: [String: Any]) -> Bool {
        if let b = extractBool(payload["authenticated"]) {
            return b
        }

        if let b = extractBool(payload["logged_in"]) {
            return b
        }

        if let b = extractBool(payload["is_logged_in"]) {
            return b
        }

        if let b = extractBool(payload["isAuthenticated"]) {
            return b
        }

        let bodyClass = extractString(payload["body_class"]).lowercased()
        if bodyClass.contains("logged-in") {
            return true
        }

        let href = extractString(payload["href"]).lowercased()
        let path = extractString(payload["current_path"]).lowercased()

        if href.contains("/my-account")
            || href.contains("/account/")
            || path.contains("/my-account")
            || path.contains("/account/") {
            return true
        }

        return false
    }

    private func hasAnyAuthHint(_ payload: [String: Any]) -> Bool {
        if payload.keys.contains("authenticated")
            || payload.keys.contains("logged_in")
            || payload.keys.contains("is_logged_in")
            || payload.keys.contains("isAuthenticated") {
            return true
        }

        let bodyClass = extractString(payload["body_class"]).lowercased()
        return bodyClass.contains("logged-in")
    }

    private func applyAuthorized(mode newMode: Mode, wpRole newRole: String) {
        mode = newMode
        wpRole = newRole
        persistAuthorized(mode: newMode, wpRole: newRole)
    }

    private func applyGuest(clearPersisted: Bool) {
        mode = .guest
        wpRole = "guest"

        if clearPersisted {
            clearPersistedAuthorizedRole()
        }
    }

    private func keepAuthorizedRoleIfPossible() {
        if let currentAuthorized = currentAuthorizedMode() {
            mode = currentAuthorized
            wpRole = wpRoleForMode(currentAuthorized)
            return
        }

        if let persisted = persistedAuthorizedMode() {
            applyAuthorized(mode: persisted, wpRole: wpRoleForMode(persisted))
            return
        }

        applyGuest(clearPersisted: false)
    }

    private func currentAuthorizedMode() -> Mode? {
        mode == .guest ? nil : mode
    }

    private func wpRoleForMode(_ mode: Mode) -> String {
        switch mode {
        case .guest:
            return "guest"
        case .client:
            return "client"
        case .worker:
            return "worker"
        case .accountant:
            return "accountant"
        case .admin:
            return "admin"
        case .owner:
            return "owner"
        case .menager:
            return "menager"
        }
    }

    private func persistAuthorized(mode: Mode, wpRole: String) {
        guard mode != .guest else {
            return
        }

        UserDefaults.standard.set(mode.rawValue, forKey: storedModeKey)
        UserDefaults.standard.set(wpRole, forKey: storedRoleKey)
    }

    private func clearPersistedAuthorizedRole() {
        UserDefaults.standard.removeObject(forKey: storedModeKey)
        UserDefaults.standard.removeObject(forKey: storedRoleKey)
    }

    private func restorePersistedAuthorizedRoleIfNeeded() {
        guard mode == .guest else {
            return
        }

        guard let persisted = persistedAuthorizedMode() else {
            return
        }

        mode = persisted
        wpRole = UserDefaults.standard.string(forKey: storedRoleKey) ?? wpRoleForMode(persisted)
    }

    private func persistedAuthorizedMode() -> Mode? {
        guard
            let raw = UserDefaults.standard.string(forKey: storedModeKey),
            let stored = Mode(rawValue: raw),
            stored != .guest
        else {
            return nil
        }

        return stored
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        for needle in needles where text.contains(needle) {
            return true
        }
        return false
    }

    private func extractString(_ value: Any?) -> String {
        if let s = value as? String {
            return s
        }

        if let n = value as? NSNumber {
            return n.stringValue
        }

        return ""
    }

    private func extractInt(_ value: Any?) -> Int? {
        if let i = value as? Int {
            return i
        }

        if let n = value as? NSNumber {
            return n.intValue
        }

        if let s = value as? String {
            return Int(s)
        }

        return nil
    }

    private func extractBool(_ value: Any?) -> Bool? {
        if let b = value as? Bool {
            return b
        }

        if let n = value as? NSNumber {
            return n.boolValue
        }

        if let s = value as? String {
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if v == "true" || v == "1" || v == "yes" {
                return true
            }

            if v == "false" || v == "0" || v == "no" {
                return false
            }
        }

        return nil
    }
}
