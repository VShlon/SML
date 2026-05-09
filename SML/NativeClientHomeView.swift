//
//  NativeClientHomeView.swift
//  SML
//
//  Native SwiftUI dashboard shown to logged-in clients.
//  Shows quick access to all client account sections.
//

import SwiftUI
import UIKit

// MARK: - Tab switch helper

private func open(_ tab: Tab) {
    NotificationCenter.default.post(
        name: .smlSwitchTab,
        object: nil,
        userInfo: ["tab": tab.rawValue]
    )
}

// MARK: - Open a page in a full-screen sheet (uses existing MainWindowPage system)

private func openPage(title: String, urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NotificationCenter.default.post(
        name: .smlPresentMainWindowPage,
        object: nil,
        userInfo: ["title": title, "url": url]
    )
}

// MARK: - Main view

struct NativeClientHomeView: View {

    private let brand = Color(red: 67 / 255.0, green: 130 / 255.0, blue: 57 / 255.0)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                quickActionsSection
                secondaryActionsSection
                contactSection
            }
        }
        .background(Color(UIColor.systemBackground))
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 30/255, green: 80/255, blue: 25/255),
                    brand
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 200)

            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 240, height: 240)
                .offset(x: 140, y: -40)

            VStack(alignment: .leading, spacing: 8) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 28)
                    .colorMultiply(.white)

                Spacer().frame(height: 4)

                Text("My Account")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                Text("St. Marys Landscaping")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .padding(.top, 60)
        }
    }

    // MARK: - Primary quick actions (2 x 2 grid)

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Access")
                .font(.system(size: 17, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 24)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                quickCard(
                    icon: "list.bullet.clipboard",
                    title: "My Requests",
                    subtitle: "View & track projects",
                    action: { open(.left2) }
                )
                quickCard(
                    icon: "paperplane",
                    title: "New Request",
                    subtitle: "Start a new service",
                    action: { open(.center) }
                )
                quickCard(
                    icon: "clock.arrow.circlepath",
                    title: "Order History",
                    subtitle: "Completed services",
                    action: { openPage(title: "Order History", urlString: "https://stmaryslandscaping.ca/order-history/") }
                )
                quickCard(
                    icon: "mappin.and.ellipse",
                    title: "My Addresses",
                    subtitle: "Manage properties",
                    action: { openPage(title: "Addresses", urlString: "https://stmaryslandscaping.ca/account-addresses/") }
                )
            }
            .padding(.horizontal, 16)
        }
    }

    private func quickCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(brand.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(brand)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Secondary actions

    private var secondaryActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account")
                .font(.system(size: 17, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 24)

            VStack(spacing: 0) {
                secondaryRow(icon: "person.crop.circle", title: "Account Details", action: {
                    openPage(title: "Account Details", urlString: "https://stmaryslandscaping.ca/account/")
                })
                Divider().padding(.leading, 54)
                secondaryRow(icon: "exclamationmark.bubble", title: "Support / Report", action: {
                    openPage(title: "Support", urlString: "https://stmaryslandscaping.ca/account-report/")
                })
            }
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func secondaryRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(brand.opacity(0.1))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(brand)
                }

                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Contact

    private var contactSection: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 24) {
                contactItem(icon: "phone", label: "+1 (519) 284-3111", action: {
                    if let url = URL(string: "tel:+15192843111") {
                        UIApplication.shared.open(url)
                    }
                })
                Divider().frame(height: 32)
                contactItem(icon: "envelope", label: "info@stmaryslandscaping.ca", action: {
                    if let url = URL(string: "mailto:info@stmaryslandscaping.ca") {
                        UIApplication.shared.open(url)
                    }
                })
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Text("Licensed and insured · St. Marys & surrounding areas")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .padding(.top, 8)
    }

    private func contactItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(brand)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
