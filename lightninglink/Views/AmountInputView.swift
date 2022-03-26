//
//  AmountInput.swift
//  lightninglink
//
//  Created by William Casarin on 2022-03-25.
//

import SwiftUI
import Combine

struct AmountInput: View {
    let text: Binding<String>
    let onReceive: (String) -> ()

    var body: some View {
        Form {
            Section {
                HStack(alignment: .lastTextBaseline) {
                    TextField("10,000", text: self.text)
                        .font(.title)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onReceive(Just(self.text)) {
                            onReceive($0.wrappedValue)
                        }
                    Text("sats")
                }
            }
        }
        .frame(height: 100)
    }
}


