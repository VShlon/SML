//
//  PushState.swift
//  SMC
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - Источник правды для APNS token + deviceId
//  - При тапе по push: парсит payload (userInfo["sml"]) и публикует openCommand
//  - Хранит Face ID настройки логина
//

import Foundation
import UIKit
import Combine
import Security
import LocalAuthentication

final class SMCBiometricSettings {
    static let shared = SMCBiometricSettings()
    private let enabledKey = "sml.faceid.enabled"
    private init() {}
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
        guard let data = try? JSONEncoder().encode(login) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
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
        guard status == errSecSuccess, let data = result as? Data else { return nil }
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

final class BiometricAuthManager {
    static let shared = BiometricAuthManager()
    private init() {}

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
        let did = UIDevice.current.identifierForVendor?.uuidString ?? ""
        deviceId = did.isEmpty ? "ios-device" : did
    }

    func setApnsToken(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        if apnsToken == t { return }
        apnsToken = t
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

    // MARK: - Remote push payload

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        let sml = extractDict(userInfo["sml"])

        let type = (extractString(sml["type"]) ?? "custom").trimmingCharacters(in: .whitespacesAndNewlines)
        let event = (extractString(sml["event"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let deeplinkStr = extractString(sml["deeplink"])
        let meta = extractDict(sml["meta"])
        let url = buildURL(deeplink: deeplinkStr, type: type, meta: meta)

        openCommand = PushOpenCommand(
            id: UUID(),
            type: type,
            event: event,
            url: url,
            meta: meta
        )
    }

    // MARK: - URL builder

    private func buildURL(deeplink: String?, type: String, meta: [String: Any]) -> URL? {
        let s = (deeplink ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty {
            if s.lowercased().hasPrefix("https://") || s.lowercased().hasPrefix("http://") {
                return URL(string: s)
            }

            if s.lowercased().hasPrefix("sml://") {
                let rest = String(s.dropFirst("sml://".count))
                let path = rest.hasPrefix("/") ? rest : "/" + rest
                return URL(string: path, relativeTo: base)?.absoluteURL
            }

            if s.hasPrefix("/") {
                return URL(string: s, relativeTo: base)?.absoluteURL
            }

            return URL(string: "/" + s, relativeTo: base)?.absoluteURL
        }

        let t = type.lowercased()

        if t == "tasks" {
            if let taskId = extractInt(meta["task_id"]), taskId > 0 {
                return URL(string: "/all-tasks/?task_id=\(taskId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/all-tasks/", relativeTo: base)?.absoluteURL
        }

        if t == "report" {
            if let reportId = extractInt(meta["report_id"]), reportId > 0 {
                return URL(string: "/report/?report_id=\(reportId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/report/", relativeTo: base)?.absoluteURL
        }

        if t == "paystubs" || t == "payroll" {
            return URL(string: "/payroll-review/", relativeTo: base)?.absoluteURL
        }

        if t == "invoices" {
            if let invoiceId = extractInt(meta["invoice_id"]), invoiceId > 0 {
                return URL(string: "/invoices/?invoice_id=\(invoiceId)", relativeTo: base)?.absoluteURL
            }
            return URL(string: "/invoices/", relativeTo: base)?.absoluteURL
        }

        if t == "requests" || t == "orders" {
            return URL(string: "/my-requests/", relativeTo: base)?.absoluteURL
        }

        return URL(string: "/", relativeTo: base)?.absoluteURL
    }

    // MARK: - Helpers

    private func extractDict(_ value: Any?) -> [String: Any] {
        if let d = value as? [String: Any] { return d }
        if let d = value as? NSDictionary {
            var out: [String: Any] = [:]
            for (k, v) in d {
                if let ks = k as? String {
                    out[ks] = v
                }
            }
            return out
        }
        return [:]
    }

    private func extractString(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private func extractInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }
}
