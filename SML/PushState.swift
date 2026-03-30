//
//  PushState.swift
//  SML
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - Источник правды для APNS token + deviceId
//  - При тапе по push: парсит payload и публикует openCommand
//  - Хранит Face ID настройки логина
//  - Строит deeplink с учетом роли пользователя
//

import Foundation
import UIKit
import Combine
import Security
import LocalAuthentication

final class SMCBiometricSettings {
    static let shared = SMCBiometricSettings()

    private let enabledKey = "sml.faceid.enabled"

    private init() { }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}

struct SMCStoredLogin: Codable {
    let username: String
    let password: String
}

enum SMCKeychain {
    private static let service = "ca.stmaryslandscaping.app.biometric-login"
    private static let account = "primary-login"

    static func save(login: SMCStoredLogin) -> Bool {
        guard let data = try? JSONEncoder().encode(login) else {
            return false
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func readLogin() -> SMCStoredLogin? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(SMCStoredLogin.self, from: data)
    }

    static func deleteLogin() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func hasLogin() -> Bool {
        readLogin() != nil
    }
}



enum SMCDeviceRegistrationKeychain {
    private static let service = "ca.stmaryslandscaping.app.push-registration"
    private static let account = "stable-device-id"

    static func readDeviceId() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            return ""
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func saveDeviceId(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let data = normalized.data(using: .utf8) else {
            return false
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func stableDeviceId() -> String {
        let stored = readDeviceId()
        if !stored.isEmpty {
            return stored
        }

        let generated = UIDevice.current.identifierForVendor?.uuidString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = !generated.isEmpty ? generated : UUID().uuidString.lowercased()
        _ = saveDeviceId(fallback)
        return fallback
    }
}

final class BiometricAuthManager {
    static let shared = BiometricAuthManager()

    private init() { }

    func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}

@MainActor
final class PushState: ObservableObject {

    static let shared = PushState()

    @Published private(set) var apnsToken: String = ""
    @Published private(set) var deviceId: String = ""

    @Published var biometricEnabled: Bool = SMCBiometricSettings.shared.isEnabled
    @Published var hasBiometricLogin: Bool = SMCKeychain.hasLogin()

    struct PushOpenCommand {
        let id: UUID
        let type: String
        let event: String
        let url: URL?
        let meta: [String: Any]
    }

    @Published var openCommand: PushOpenCommand? = nil

    private let base = URL(string: "https://stmaryslandscaping.ca")!

    private init() {
        let stableId = SMCDeviceRegistrationKeychain.stableDeviceId()
        deviceId = stableId.isEmpty ? "ios-device" : stableId
    }

    func setApnsToken(_ token: String) {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return }
        if apnsToken == normalized { return }
        apnsToken = normalized
    }

    func setBiometricEnabled(_ enabled: Bool) {
        biometricEnabled = enabled
        SMCBiometricSettings.shared.isEnabled = enabled

        if !enabled {
            SMCKeychain.deleteLogin()
            hasBiometricLogin = false
        }
    }

    func refreshBiometricState() {
        biometricEnabled = SMCBiometricSettings.shared.isEnabled
        hasBiometricLogin = SMCKeychain.hasLogin()
    }

    func consumeOpenCommand(_ cmd: PushOpenCommand) {
        if openCommand?.id == cmd.id {
            openCommand = nil
        }
    }

    // MARK: - Обработка remote push payload

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        let payload = extractPayload(userInfo)
        let type = (extractString(payload["type"]) ?? "custom").trimmingCharacters(in: .whitespacesAndNewlines)
        let event = (extractString(payload["event"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let deeplink = extractString(payload["deeplink"])
        let meta = extractDict(payload["meta"])
        let url = buildURL(deeplink: deeplink, type: type, event: event, meta: meta)

        openCommand = PushOpenCommand(
            id: UUID(),
            type: type,
            event: event,
            url: url,
            meta: meta
        )
    }

    // MARK: - Построение URL

    private func buildURL(deeplink: String?, type: String, event: String, meta: [String: Any]) -> URL? {
        let rawDeeplink = (deeplink ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !rawDeeplink.isEmpty {
            if rawDeeplink.lowercased().hasPrefix("https://") || rawDeeplink.lowercased().hasPrefix("http://") {
                return URL(string: rawDeeplink)
            }

            if rawDeeplink.lowercased().hasPrefix("sml://") {
                let rest = String(rawDeeplink.dropFirst("sml://".count))
                let path = rest.hasPrefix("/") ? rest : "/" + rest
                return URL(string: path, relativeTo: base)?.absoluteURL
            }

            if rawDeeplink.hasPrefix("/") {
                return URL(string: rawDeeplink, relativeTo: base)?.absoluteURL
            }

            return URL(string: "/" + rawDeeplink, relativeTo: base)?.absoluteURL
        }

        let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedEvent = event.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let role = RoleState.shared.mode

        if normalizedType == "tasks" || normalizedType == "task" || normalizedEvent.contains("task") {
            return buildTasksURL(meta: meta, role: role)
        }

        if normalizedType == "report" || normalizedEvent.contains("report") {
            return buildReportURL(meta: meta, role: role)
        }

        if normalizedType == "paystubs" || normalizedType == "payroll" || normalizedEvent.contains("paystub") || normalizedEvent.contains("payroll") {
            return buildPayrollURL(meta: meta, role: role)
        }

        if normalizedType == "invoices" || normalizedType == "invoice" {
            if let invoiceId = extractInt(meta["invoice_id"]), invoiceId > 0 {
                return URL(string: "/account/?invoice_id=\(invoiceId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/account/", relativeTo: base)?.absoluteURL
        }

        if normalizedType == "requests" || normalizedType == "request" || normalizedType == "orders" || normalizedType == "order" {
            return URL(string: "/account/", relativeTo: base)?.absoluteURL
        }

        if normalizedType == "notifications" {
            return URL(string: "/account/", relativeTo: base)?.absoluteURL
        }

        return URL(string: "/", relativeTo: base)?.absoluteURL
    }

    private func buildTasksURL(meta: [String: Any], role: RoleState.Mode) -> URL? {
        let taskId = extractInt(meta["task_id"])

        switch role {
        case .worker:
            if let taskId, taskId > 0 {
                return URL(string: "/tasks-today/?task_id=\(taskId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/tasks-today/", relativeTo: base)?.absoluteURL

        case .accountant:
            if let taskId, taskId > 0 {
                return URL(string: "/workday/?task_id=\(taskId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/workday/", relativeTo: base)?.absoluteURL

        case .admin, .owner, .menager:
            if let taskId, taskId > 0 {
                return URL(string: "/all-tasks/?task_id=\(taskId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/all-tasks/", relativeTo: base)?.absoluteURL

        case .client, .guest:
            return URL(string: "/", relativeTo: base)?.absoluteURL
        }
    }

    private func buildReportURL(meta: [String: Any], role: RoleState.Mode) -> URL? {
        let reportId = extractInt(meta["report_id"])

        switch role {
        case .worker:
            if let reportId, reportId > 0 {
                return URL(string: "/report/?report_id=\(reportId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/report/", relativeTo: base)?.absoluteURL

        case .accountant:
            if let reportId, reportId > 0 {
                return URL(string: "/workday/?report_id=\(reportId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/workday/", relativeTo: base)?.absoluteURL

        case .admin, .owner:
            if let reportId, reportId > 0 {
                return URL(string: "/workspace/?report_id=\(reportId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/workspace/", relativeTo: base)?.absoluteURL

        case .menager:
            if let reportId, reportId > 0 {
                return URL(string: "/workday/?report_id=\(reportId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/workday/", relativeTo: base)?.absoluteURL

        case .client, .guest:
            return URL(string: "/", relativeTo: base)?.absoluteURL
        }
    }

    private func buildPayrollURL(meta: [String: Any], role: RoleState.Mode) -> URL? {
        let paystubId = extractInt(meta["paystub_id"])
        let payrollId = extractInt(meta["payroll_id"])

        switch role {
        case .accountant:
            if let paystubId, paystubId > 0 {
                return URL(string: "/payroll-review/?paystub_id=\(paystubId)", relativeTo: base)?.absoluteURL
            }
            if let payrollId, payrollId > 0 {
                return URL(string: "/payroll-review/?payroll_id=\(payrollId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/payroll-review/", relativeTo: base)?.absoluteURL

        case .worker:
            if let paystubId, paystubId > 0 {
                return URL(string: "/workday/?paystub_id=\(paystubId)", relativeTo: base)?.absoluteURL
            }
            if let payrollId, payrollId > 0 {
                return URL(string: "/workday/?payroll_id=\(payrollId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/workday/", relativeTo: base)?.absoluteURL

        case .menager:
            if let paystubId, paystubId > 0 {
                return URL(string: "/workday/?paystub_id=\(paystubId)", relativeTo: base)?.absoluteURL
            }
            if let payrollId, payrollId > 0 {
                return URL(string: "/workday/?payroll_id=\(payrollId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/workday/", relativeTo: base)?.absoluteURL

        case .admin, .owner:
            if let paystubId, paystubId > 0 {
                return URL(string: "/workspace/?paystub_id=\(paystubId)", relativeTo: base)?.absoluteURL
            }
            if let payrollId, payrollId > 0 {
                return URL(string: "/workspace/?payroll_id=\(payrollId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/workspace/", relativeTo: base)?.absoluteURL

        case .client, .guest:
            return URL(string: "/", relativeTo: base)?.absoluteURL
        }
    }

    // MARK: - Вспомогательные методы

    private func extractPayload(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        if let nested = userInfo["sml"] {
            let dict = extractDict(nested)
            if !dict.isEmpty {
                return dict
            }
        }

        var topLevel: [String: Any] = [:]
        for (key, value) in userInfo {
            if let stringKey = key as? String {
                topLevel[stringKey] = value
            }
        }
        return topLevel
    }

    private func extractDict(_ value: Any?) -> [String: Any] {
        if let d = value as? [String: Any] {
            return d
        }

        if let d = value as? NSDictionary {
            var out: [String: Any] = [:]
            for (k, v) in d {
                if let key = k as? String {
                    out[key] = v
                }
            }
            return out
        }

        return [:]
    }

    private func extractString(_ value: Any?) -> String? {
        if let s = value as? String {
            return s
        }

        if let n = value as? NSNumber {
            return n.stringValue
        }

        return nil
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
}
