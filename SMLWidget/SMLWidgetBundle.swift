//
//  SMLWidgetBundle.swift
//  SMLWidget
//

import WidgetKit
import SwiftUI

@main
struct SMLWidgetBundle: WidgetBundle {
    var body: some Widget {
        SMLWidget()
        if #available(iOSApplicationExtension 16.2, *) {
            WorkdayLiveActivity()
            OrderLiveActivity()
        }
    }
}
