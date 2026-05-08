//
//  QuoteRequestView.swift
//  SML
//
//  Version: 2.0.0
//  Author: Nuvren.com
//
//  Purpose:
//  - Fully native SwiftUI quote request form.
//  - Loads services and materials catalog from REST /sml/v1/catalog.
//  - Submits to POST /wp-json/sml/v1/quote-request — same backend as the website.
//  - Satisfies Apple Guideline 4.2.2: native interactive functionality beyond the website.
//

import SwiftUI

struct QuoteRequestView: View {

    // MARK: - Models

    enum RequestType: String, CaseIterable {
        case service, material
        var label: String { rawValue == "service" ? "Service" : "Material" }
    }

    struct CatalogItem: Identifiable, Hashable {
        let id = UUID()
        let slug:  String
        let label: String
        let price: String
    }

    // MARK: - Catalog

    @State private var services:       [CatalogItem] = []
    @State private var materials:      [CatalogItem] = []
    @State private var catalogLoading  = true
    @State private var catalogError:   String?       = nil

    // MARK: - Form

    @State private var requestType:    RequestType   = .service
    @State private var selectedSlug:   String        = ""
    @State private var name:           String        = ""
    @State private var email:          String        = ""
    @State private var phone:          String        = ""
    @State private var address:        String        = ""
    @State private var preferredDate:  Date          = Date().addingTimeInterval(86400)
    @State private var useDate:        Bool          = false
    @State private var quantity:       Double        = 1.0
    @State private var notes:          String        = ""

    // MARK: - Submit

    @State private var submitting  = false
    @State private var submitDone  = false
    @State private var submitError: String? = nil

    // MARK: - Design

    private let brand = Color(red: 67/255, green: 130/255, blue: 57/255)
    private let bg    = Color(red: 247/255, green: 248/255, blue: 246/255)

    // MARK: - Computed

    private var currentItems: [CatalogItem] {
        requestType == .service ? services : materials
    }

    private var isMaterial: Bool { requestType == .material }

    private var canSubmit: Bool {
        !selectedSlug.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !phone.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                if submitDone {
                    successView
                } else if catalogLoading {
                    loadingView
                } else if let err = catalogError {
                    errorView(message: err)
                } else {
                    formView
                }
            }
            .navigationTitle("New Request")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.light)
        .task { await loadCatalog() }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().tint(brand)
            Text("Loading catalog...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(brand)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await loadCatalog() }
            }
            .buttonStyle(SMLPrimaryButtonStyle(brand: brand))
            .padding(.horizontal, 48)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(brand)
            VStack(spacing: 10) {
                Text("Request Sent!")
                    .font(.title2.bold())
                Text("We received your request and will get back to you shortly.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Button("Send Another Request") { resetForm() }
                .buttonStyle(SMLPrimaryButtonStyle(brand: brand))
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Form View

    private var formView: some View {
        ScrollView {
            VStack(spacing: 20) {
                typeSection
                itemSection
                contactSection
                addressSection
                if isMaterial { quantitySection }
                dateSection
                notesSection
                submitSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Form Sections

    private var typeSection: some View {
        formCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Request Type")
                Picker("Type", selection: $requestType) {
                    ForEach(RequestType.allCases, id: \.self) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: requestType) { _, _ in selectedSlug = "" }
            }
        }
    }

    private var itemSection: some View {
        formCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(isMaterial ? "Select Material" : "Select Service")

                if currentItems.isEmpty {
                    Text("No \(requestType.label.lowercased())s available at this time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Menu {
                        ForEach(currentItems) { item in
                            Button(item.label) { selectedSlug = item.slug }
                        }
                    } label: {
                        HStack {
                            Text(currentItems.first(where: { $0.slug == selectedSlug })?.label ?? "Select \(requestType.label.lowercased())...")
                                .foregroundStyle(selectedSlug.isEmpty ? Color(.placeholderText) : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(brand)
                        }
                        .padding(14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var contactSection: some View {
        formCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Contact Information")
                VStack(spacing: 0) {
                    inputRow(icon: "person", placeholder: "Full name", text: $name, keyboard: .default, cap: .words)
                    divider
                    inputRow(icon: "envelope", placeholder: "Email address", text: $email, keyboard: .emailAddress, cap: .never)
                    divider
                    inputRow(icon: "phone", placeholder: "Phone number", text: $phone, keyboard: .phonePad, cap: .never)
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var addressSection: some View {
        formCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Property Address")
                inputRow(icon: "mappin.and.ellipse", placeholder: "Street address, city", text: $address, keyboard: .default, cap: .words)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var quantitySection: some View {
        formCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Quantity")
                HStack(spacing: 20) {
                    Button {
                        if quantity > 0.5 { quantity = max(0.5, (quantity - 0.5 * 10).rounded(.toNearestOrAwayFromZero) / 10) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(quantity > 0.5 ? brand : Color(.systemGray3))
                    }
                    .disabled(quantity <= 0.5)

                    Spacer()

                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", quantity))
                            .font(.title.monospacedDigit().bold())
                            .foregroundStyle(.primary)
                        Text("cubic yards")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        quantity = min(999, (quantity + 0.5 * 10).rounded(.toNearestOrAwayFromZero) / 10)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(brand)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var dateSection: some View {
        formCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Preferred Date")
                Toggle(isOn: $useDate) {
                    Label("Set a preferred date", systemImage: "calendar")
                        .foregroundStyle(.primary)
                }
                .tint(brand)

                if useDate {
                    Divider()
                    DatePicker(
                        "Select date",
                        selection: $preferredDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(brand)
                }
            }
        }
    }

    private var notesSection: some View {
        formCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Additional Notes")
                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Describe your project, timeline, or any special requirements...")
                            .foregroundStyle(Color(.placeholderText))
                            .font(.body)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $notes)
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                }
                .padding(4)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var submitSection: some View {
        VStack(spacing: 12) {
            if let err = submitError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(err)
                }
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            }

            Button {
                Task { await submitForm() }
            } label: {
                ZStack {
                    if submitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Send Request")
                            .font(.body.bold())
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(SMLPrimaryButtonStyle(brand: brand))
            .disabled(!canSubmit || submitting)

            if !canSubmit {
                Text("Please fill in all required fields")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Reusable Components

    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(brand.opacity(0.8))
            .kerning(0.5)
    }

    private func inputRow(icon: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType, cap: TextInputAutocapitalization) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(brand)
                .frame(width: 20)
                .padding(.leading, 12)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(cap)
                .autocorrectionDisabled()
                .padding(.vertical, 13)
                .padding(.trailing, 12)
        }
    }

    private var divider: some View {
        Divider()
            .padding(.leading, 44)
    }

    // MARK: - Networking

    private func loadCatalog() async {
        await MainActor.run {
            catalogLoading = true
            catalogError   = nil
        }

        guard let url = URL(string: "https://stmaryslandscaping.ca/wp-json/sml/v1/catalog") else {
            await MainActor.run { catalogLoading = false; catalogError = "Configuration error." }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard
                let json      = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                json["ok"] as? Bool == true
            else { throw URLError(.badServerResponse) }

            let rawServices  = (json["services"]  as? [[String: Any]]) ?? []
            let rawMaterials = (json["materials"] as? [[String: Any]]) ?? []

            let parsedServices = rawServices.compactMap { d -> CatalogItem? in
                guard let slug = d["slug"] as? String, let label = d["label"] as? String else { return nil }
                return CatalogItem(slug: slug, label: label, price: "")
            }
            let parsedMaterials = rawMaterials.compactMap { d -> CatalogItem? in
                guard let slug = d["slug"] as? String, let label = d["label"] as? String else { return nil }
                return CatalogItem(slug: slug, label: label, price: (d["price"] as? String) ?? "")
            }

            await MainActor.run {
                services       = parsedServices
                materials      = parsedMaterials
                catalogLoading = false
            }
        } catch {
            await MainActor.run {
                catalogError   = "Could not load the catalog. Please check your connection and try again."
                catalogLoading = false
            }
        }
    }

    private func submitForm() async {
        guard canSubmit else { return }

        await MainActor.run {
            submitting  = true
            submitError = nil
        }

        var body: [String: Any] = [
            "type":    requestType.rawValue,
            "item":    selectedSlug,
            "name":    name.trimmingCharacters(in: .whitespaces),
            "email":   email.trimmingCharacters(in: .whitespaces),
            "phone":   phone.trimmingCharacters(in: .whitespaces),
            "address": address.trimmingCharacters(in: .whitespaces),
            "notes":   notes.trimmingCharacters(in: .whitespaces),
        ]

        if isMaterial { body["quantity"] = quantity }

        if useDate {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            body["preferred_date"] = fmt.string(from: preferredDate)
        }

        guard
            let url     = URL(string: "https://stmaryslandscaping.ca/wp-json/sml/v1/quote-request"),
            let payload = try? JSONSerialization.data(withJSONObject: body)
        else {
            await MainActor.run { submitting = false; submitError = "Could not prepare request." }
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody   = payload

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let ok   = json["ok"] as? Bool ?? false
            let msg  = json["message"] as? String ?? "Something went wrong. Please try again."

            await MainActor.run {
                submitting = false
                if ok || (200..<300).contains(code) {
                    submitDone = true
                } else {
                    submitError = msg
                }
            }
        } catch {
            await MainActor.run {
                submitting  = false
                submitError = "Network error. Please check your connection and try again."
            }
        }
    }

    private func resetForm() {
        requestType   = .service
        selectedSlug  = ""
        name          = ""
        email         = ""
        phone         = ""
        address       = ""
        notes         = ""
        useDate       = false
        quantity      = 1.0
        submitDone    = false
        submitError   = nil
    }
}

// MARK: - Primary Button Style

private struct SMLPrimaryButtonStyle: ButtonStyle {
    let brand: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                brand.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1.0) : 0.38),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .foregroundStyle(.white)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
