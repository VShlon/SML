//
//  MoreRootView.swift
//  sml
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - Общий More-экран для всех ролей.
//  - Содержит Account, Notifications, Company, Social, Contact, Security.
//  - Внутренние ссылки из More открываются в главном окне приложения.
//

import SwiftUI
import UIKit
import LocalAuthentication

struct SMLMoreRootView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var appNavigation = AppNavigationState.shared

    private let linkAccount   = AppConfig.url("/account/")
    private let linkServices  = AppConfig.url("/services/")
    private let linkProjects  = AppConfig.url("/projects/")
    private let linkMaterials = AppConfig.url("/materials/")
    private let linkCareers   = AppConfig.url("/careers/")
    private let linkAbout     = AppConfig.url("/about/")
    private let linkFAQ       = AppConfig.url("/faq/")
    private let linkContact   = AppConfig.url("/contact/")
    private let linkPrivacy   = AppConfig.url("/privacy-policy/")
    private let linkTerms     = AppConfig.url("/terms-of-service/")

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { openInMainWindow(linkAccount) } label: {
                        row(system: "person", title: "Account")
                    }

                    NavigationLink {
                        NotificationsView()
                    } label: {
                        row(system: "bell", title: "Notifications", color: Color(uiColor: AppConfig.brandColor))
                    }
                }

                Section("COMPANY") {
                    Button { openInMainWindow(linkServices) } label: { row(system: "leaf", title: "Services") }
                    Button { openInMainWindow(linkProjects) } label: { row(system: "photo.on.rectangle", title: "Projects") }
                    Button { openInMainWindow(linkMaterials) } label: { row(system: "cube.box", title: "Materials") }
                    Button { openInMainWindow(linkCareers) } label: { row(system: "briefcase", title: "Careers") }
                    Button { openInMainWindow(linkAbout) } label: { row(system: "info.circle", title: "About") }
                    Button { openInMainWindow(linkFAQ) } label: { row(system: "questionmark.circle", title: "FAQ") }
                    Button { openInMainWindow(linkContact) } label: { row(system: "envelope", title: "Contact") }
                    Button { openInMainWindow(linkPrivacy) } label: { row(system: "hand.raised", title: "Privacy Policy") }
                    Button { openInMainWindow(linkTerms) } label: { row(system: "doc.text", title: "Terms of Service") }
                }

                Section("SOCIAL") {
                    Button { openExternal(AppConfig.instagramURL) } label: {
                        rowCustomIcon(assetName: "icon_instagram", fallbackSystem: "camera", title: "Instagram")
                    }
                    Button { openExternal(AppConfig.facebookURL) } label: {
                        rowCustomIcon(assetName: "icon_facebook", fallbackSystem: "f.cursive", title: "Facebook")
                    }
                }

                Section("CONTACT") {
                    Button { callPhone() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "phone")
                                .frame(width: 22)
                            Text(AppConfig.phoneDisplay)
                            Spacer()
                        }
                    }

                    Link(destination: URL(string: "mailto:\(AppConfig.email)")!) {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope")
                                .frame(width: 22)
                            Text(AppConfig.email)
                            Spacer()
                        }
                    }
                }

                Section("SECURITY") {
                    NavigationLink {
                        FaceIDSettingsScreen()
                    } label: {
                        row(system: "faceid", title: "Face ID")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .preferredColorScheme(.light)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(Color(uiColor: AppConfig.brandColor))
    }

    private func row(system: String, title: String, color: Color = Color(uiColor: AppConfig.brandColor)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: system)
                .frame(width: 22)
            Text(title)
            Spacer()
        }
        .foregroundStyle(color)
    }

    private func rowCustomIcon(assetName: String, fallbackSystem: String, title: String) -> some View {
        HStack(spacing: 12) {
            Group {
                if UIImage(named: assetName) != nil {
                    Image(assetName)
                        .renderingMode(.template)
                } else {
                    Image(systemName: fallbackSystem)
                }
            }
            .frame(width: 22)

            Text(title)
            Spacer()
        }
        .foregroundStyle(Color(uiColor: AppConfig.brandColor))
    }

    private func openInMainWindow(_ url: URL) {
        appNavigation.openInMainWindow(url, keepCurrentTab: false)
        dismiss()
    }

    private func openExternal(_ url: URL) {
        UIApplication.shared.open(url)
    }

    private func callPhone() {
        guard let url = URL(string: "tel://\(AppConfig.phoneDigits)") else { return }
        UIApplication.shared.open(url)
    }
}

private struct FaceIDSettingsScreen: View {
    @AppStorage("sml_face_id_enabled") private var isEnabled: Bool = false
    @State private var biometryTitle: String = "Face ID"
    @State private var isAvailable: Bool = false
    @State private var detailText: String = "Protect the app when it reopens or returns to the foreground."

    var body: some View {
        List {
            Section {
                Toggle(isOn: $isEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Use \(biometryTitle)")
                        Text(detailText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!isAvailable)
            }

            if !isAvailable {
                Section {
                    Text("Biometric unlock is unavailable on this device.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Face ID")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshBiometryState()
        }
    }

    private func refreshBiometryState() {
        let context = LAContext()
        var error: NSError?
        isAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        switch context.biometryType {
        case .faceID:
            biometryTitle = "Face ID"
        case .touchID:
            biometryTitle = "Touch ID"
        default:
            biometryTitle = "Face ID"
        }

        if isAvailable {
            detailText = "Protect the app when it reopens or returns to the foreground."
        } else {
            detailText = error?.localizedDescription ?? "Biometric unlock is unavailable on this device."
            isEnabled = false
        }
    }
}
