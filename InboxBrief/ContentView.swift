//
//  ContentView.swift
//  InboxBrief
//
//  Created by Tin Pham on 5/9/26.
//

import SwiftUI

struct ContentView: View {
    let briefingViewModel: BriefingViewModel
    let accountsViewModel: AccountsViewModel

    var body: some View {
        BriefingView(
            viewModel: briefingViewModel,
            accountsViewModel: accountsViewModel
        )
    }
}
