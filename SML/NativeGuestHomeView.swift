//
//  NativeGuestHomeView.swift
//  SML
//
//  Native SwiftUI home screen for guests.
//  Colors, typography and layout match the website exactly.
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

extension Tab: RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue {
        case "left1":  self = .left1
        case "left2":  self = .left2
        case "center": self = .center
        case "right1": self = .right1
        case "right2": self = .right2
        default:       return nil
        }
    }
    public var rawValue: String {
        switch self {
        case .left1:  return "left1"
        case .left2:  return "left2"
        case .center: return "center"
        case .right1: return "right1"
        case .right2: return "right2"
        }
    }
}

extension Notification.Name {
    static let smlSwitchTab = Notification.Name("smlSwitchTab")
}

// MARK: - Main view

struct NativeGuestHomeView: View {

    // Website design tokens
    private let bg      = Color(red: 243/255, green: 240/255, blue: 232/255) // #F3F0E8
    private let surface = Color(red: 247/255, green: 243/255, blue: 234/255) // #F7F3EA
    private let ink     = Color(red: 18/255,  green: 22/255,  blue: 18/255)  // #121612
    private let brand   = Color(red: 67/255,  green: 130/255, blue: 57/255)  // #438239

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroSection
                statsSection
                servicesSection
                ctaSection
                contactSection
            }
        }
        .background(bg)
        .ignoresSafeArea(edges: .top)
        .tint(brand)
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {

            // Real photo background
            GeometryReader { geo in
                Image("HeroSlide")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }

            // Dark + green overlay like on the website
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.72), location: 0),
                    .init(color: Color.black.opacity(0.44), location: 0.45),
                    .init(color: Color.black.opacity(0.68), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Green accent in top-left corner
            RadialGradient(
                colors: [brand.opacity(0.45), Color.clear],
                center: .init(x: 0.18, y: 0.14),
                startRadius: 0,
                endRadius: 280
            )

            VStack(alignment: .leading, spacing: 0) {

                // Logo row
                HStack(spacing: 10) {
                    Image("SMLLeaf")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                    Text("St. Marys Landscaping")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.90))
                }

                Spacer().frame(height: 20)

                Text("Landscape\nDesign, Build\n& Care")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .lineSpacing(1)

                Spacer().frame(height: 10)

                Text("Professional landscaping for\nSt. Marys & surrounding areas.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.80))
                    .lineSpacing(3)

                Spacer().frame(height: 24)

                HStack(spacing: 10) {
                    Button {
                        open(.center)
                    } label: {
                        Text("Free Estimate")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(brand)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        open(.right1)
                    } label: {
                        Text("Our Services")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
            .padding(.top, 66)
        }
        .frame(height: 380)
    }

    // MARK: - Stats

    private var statsSection: some View {
        HStack(spacing: 0) {
            statItem(value: "1971",    label: "Established")
            statDivider
            statItem(value: "30,000+", label: "Clients served")
            statDivider
            statItem(value: "50+",     label: "Years of experience")
        }
        .padding(.vertical, 22)
        .background(surface)
        .overlay(
            Rectangle()
                .fill(ink.opacity(0.08))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var statDivider: some View {
        Rectangle()
            .fill(ink.opacity(0.12))
            .frame(width: 1, height: 36)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(brand)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ink.opacity(0.50))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Services

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 0) {

            VStack(alignment: .leading, spacing: 6) {
                Text("OUR SERVICES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(brand)
                    .tracking(1.4)
                Text("What we do")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(ink)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 20)

            VStack(spacing: 10) {
                serviceRow(
                    icon: "pencil.and.ruler.fill",
                    title: "Landscape Design",
                    desc:  "Custom plans tailored to your property and vision."
                )
                serviceRow(
                    icon: "hammer.fill",
                    title: "Installation & Build",
                    desc:  "Quality builds using materials that hold up over time."
                )
                serviceRow(
                    icon: "leaf.fill",
                    title: "Lawn & Garden Care",
                    desc:  "Ongoing maintenance to keep your property looking its best."
                )
                serviceRow(
                    icon: "snowflake",
                    title: "Winter Services",
                    desc:  "Snow removal and winter property management."
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func serviceRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(brand.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(brand)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                Text(desc)
                    .font(.system(size: 13))
                    .foregroundStyle(ink.opacity(0.54))
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ink.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 14) {
            Text("Ready to get started?")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)

            Text("Tell us about your project and we'll come back with a clear plan and a quote.")
                .font(.system(size: 14))
                .foregroundStyle(ink.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 8)

            Spacer().frame(height: 4)

            Button {
                open(.center)
            } label: {
                Text("Request a Free Estimate")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(brand)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button {
                open(.left2)
            } label: {
                Text("Sign In to My Account")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(brand.opacity(0.45), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .padding(.vertical, 12)
    }

    // MARK: - Contact

    private var contactSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ink.opacity(0.09))
                .frame(height: 1)

            HStack(spacing: 0) {
                contactBtn(icon: "phone.fill", label: "519-284-3111") {
                    if let url = URL(string: "tel:+15192843111") {
                        UIApplication.shared.open(url)
                    }
                }
                Rectangle()
                    .fill(ink.opacity(0.10))
                    .frame(width: 1, height: 28)
                contactBtn(icon: "envelope.fill", label: "info@stmaryslandscaping.ca") {
                    if let url = URL(string: "mailto:info@stmaryslandscaping.ca") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)

            Text("Licensed and insured · St. Marys & surrounding areas")
                .font(.system(size: 11))
                .foregroundStyle(ink.opacity(0.38))
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)
        }
        .background(surface)
        .overlay(
            Rectangle()
                .fill(ink.opacity(0.08))
                .frame(height: 1),
            alignment: .top
        )
    }

    private func contactBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(brand)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
