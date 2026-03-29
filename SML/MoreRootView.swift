//
//  MoreRootView.swift
//  SMC
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - More экран в стандартном iOS стиле
//  - Показ как sheet/fullScreenCover
//  - SML ссылки, контакты, соцсети и Face ID логин
//

import SwiftUI
import UIKit

struct SMCMoreRootView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var push = PushState.shared
    @State private var faceIdEnabled = SMCBiometricSettings.shared.isEnabled
    @State private var destination: MoreDestination? = nil

    private let brand = Color(red: 67 / 255.0, green: 130 / 255.0, blue: 57 / 255.0)
    private let phoneDisplay = "519-284-3111"
    private let phoneTel = "5192843111"
    private let email = "info@stmaryslandscaping.ca"

    private let linkAccount = URL(string: "https://stmaryslandscaping.ca/account/")!
    private let linkServices = URL(string: "https://stmaryslandscaping.ca/services/")!
    private let linkProjects = URL(string: "https://stmaryslandscaping.ca/projects/")!
    private let linkContact = URL(string: "https://stmaryslandscaping.ca/contact/")!
    private let linkReport = URL(string: "https://stmaryslandscaping.ca/account-report/")!
    private let linkPrivacy = URL(string: "https://stmaryslandscaping.ca/privacy-policy/")!
    private let linkTerms = URL(string: "https://stmaryslandscaping.ca/terms-of-service/")!

    private let linkInstagram = URL(string: "https://www.instagram.com/stmaryslandscaping")!
    private let linkFacebook = URL(string: "https://www.facebook.com/sml.canada/")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    navButton(.account, system: "person", title: "Account")
                    navButton(.notifications, system: "bell", title: "Notifications")
                }

                Section {
                    navButton(.services, system: "leaf", title: "Services")
                    navButton(.projects, system: "square.grid.2x2", title: "Projects")
                    navButton(.contact, system: "phone", title: "Contact")
                    navButton(.report, system: "doc.text.magnifyingglass", title: "Report")
                    navButton(.privacy, system: "hand.raised", title: "Privacy Policy")
                    navButton(.terms, system: "doc.text", title: "Terms of Service")
                } header: {
                    sectionHeader("IMPORTANT LINKS")
                }

                Section {
                    Button { openExternal(linkInstagram) } label: {
                        rowCustomIcon(assetName: "icon_instagram", fallbackSystem: "camera", title: "Instagram", showsChevron: false)
                    }
                    .buttonStyle(.plain)

                    Button { openExternal(linkFacebook) } label: {
                        rowCustomIcon(assetName: "icon_facebook", fallbackSystem: "f.cursive", title: "Facebook", showsChevron: false)
                    }
                    .buttonStyle(.plain)
                } header: {
                    sectionHeader("SOCIAL")
                }

                Section {
                    Button { callPhone() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "phone")
                                .frame(width: 22)
                            Text(phoneDisplay)
                            Spacer()
                            Text("Call")
                        }
                        .foregroundStyle(brand)
                    }
                    .buttonStyle(.plain)

                    Button { sendEmail() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope")
                                .frame(width: 22)
                            Text(email)
                            Spacer()
                            Text("Email")
                        }
                        .foregroundStyle(brand)
                    }
                    .buttonStyle(.plain)
                } header: {
                    sectionHeader("CONTACT")
                }

                Section {
                    Toggle(isOn: $faceIdEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "faceid")
                                .frame(width: 22)
                            Text("Enable Face ID")
                        }
                        .foregroundStyle(brand)
                    }
                    .tint(brand)
                    .onChange(of: faceIdEnabled) { _, isOn in
                        push.setBiometricEnabled(isOn)
                    }

                    if faceIdEnabled {
                        HStack {
                            Text("Saved login")
                            Spacer()
                            Text(push.hasBiometricLogin ? "Ready" : "Not saved yet")
                        }
                        .foregroundStyle(brand)
                    }
                } header: {
                    sectionHeader("SECURITY")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersionString())
                    }
                    .foregroundStyle(brand)
                } header: {
                    sectionHeader("APP INFO")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .preferredColorScheme(.light)
            .onAppear {
                push.refreshBiometricState()
                faceIdEnabled = push.biometricEnabled
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $destination) { screen in
                destinationView(screen)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(brand)
                }
            }
        }
        .tint(brand)
    }

    @ViewBuilder
    private func destinationView(_ screen: MoreDestination) -> some View {
        switch screen {
        case .notifications:
            NotificationsView()
                .preferredColorScheme(.light)
                .navigationTitle("Notifications")
                .navigationBarTitleDisplayMode(.inline)
        case .account:
            InAppWebScreen(title: "Account", url: linkAccount)
        case .services:
            InAppWebScreen(title: "Services", url: linkServices)
        case .projects:
            InAppWebScreen(title: "Projects", url: linkProjects)
        case .contact:
            InAppWebScreen(title: "Contact", url: linkContact)
        case .report:
            InAppWebScreen(title: "Report", url: linkReport)
        case .privacy:
            InAppWebScreen(title: "Privacy Policy", url: linkPrivacy)
        case .terms:
            InAppWebScreen(title: "Terms of Service", url: linkTerms)
        }
    }

    private func navButton(_ destinationValue: MoreDestination, system: String, title: String) -> some View {
        Button {
            destination = destinationValue
        } label: {
            row(system: system, title: title, showsChevron: true)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(brand)
            Spacer()
        }
        .textCase(nil)
    }

    private func row(system: String, title: String, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: system)
                .frame(width: 22)
            Text(title)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .foregroundStyle(brand)
    }

    private func rowCustomIcon(assetName: String, fallbackSystem: String, title: String, showsChevron: Bool) -> some View {
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
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .foregroundStyle(brand)
    }

    private func openExternal(_ url: URL) {
        UIApplication.shared.open(url)
    }

    private func callPhone() {
        guard let url = URL(string: "tel://\(phoneTel)") else { return }
        UIApplication.shared.open(url)
    }

    private func sendEmail() {
        guard let url = URL(string: "mailto:\(email)") else { return }
        UIApplication.shared.open(url)
    }

    private func appVersionString() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

private enum MoreDestination: String, Identifiable {
    case account
    case notifications
    case services
    case projects
    case contact
    case report
    case privacy
    case terms

    var id: String { rawValue }
}

private struct InAppWebScreen: View {
    let title: String
    let url: URL

    @StateObject private var push = PushState.shared

    var body: some View {
        WebView(
            url: url,
            apnsToken: push.apnsToken,
            deviceId: push.deviceId,
            biometricEnabled: push.biometricEnabled,
            hasBiometricLogin: push.hasBiometricLogin,
            command: nil
        )
        .preferredColorScheme(.light)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
