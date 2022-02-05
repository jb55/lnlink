//
//  ContentView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-01-07.
//

import SwiftUI

struct ContentView: View {
    @State private var info: GetInfo
    @State private var showingQRScanner = false

    init(info: GetInfo) {
        self.info = info
    }

    var body: some View {
        let _self = self
        VStack {
            Button("Pay") {
                showingQRScanner = true
            }
            Text(self.info.alias)
            Text("\(self.info.num_active_channels) active channels")
            Text("\(self.info.msatoshi_fees_collected / 1000) sats collected in fees")
        }
        .sheet(isPresented: $showingQRScanner) {
            QRScanner() { code in
                print(code)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView(info: .empty)
        }
    }
}
