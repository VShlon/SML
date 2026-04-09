//
//  QuoteRequestView.swift
//  SML
//
//  Version: 1.1.0
//  Author: Nuvren.com
//
//  Purpose:
//  - Request tab content: opens the New Request form for all users (guest and client).
//  - Uses the shared WKWebView session so the user is already authenticated.
//  - Satisfies Apple Guideline 4.2.2: the page is a fully interactive
//    quote-request form, not a static marketing page.
//

import SwiftUI

struct QuoteRequestView: View {

    @StateObject private var push = PushState.shared

    private let newRequestURL = URL(string: "https://stmaryslandscaping.ca/new-request/")!

    var body: some View {
        WebView(
            url: newRequestURL,
            apnsToken: push.apnsToken,
            deviceId: push.deviceId,
            biometricEnabled: push.biometricEnabled,
            hasBiometricLogin: push.hasBiometricLogin,
            command: nil
        )
        .ignoresSafeArea()
    }
}
