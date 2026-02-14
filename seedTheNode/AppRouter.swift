//
//  AppRouter.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import SwiftUI

enum AppTab: String, CaseIterable {
    case overview
    case catalog
    case upload
    case settings
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .overview
}
