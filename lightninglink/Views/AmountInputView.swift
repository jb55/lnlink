//
//  AmountInput.swift
//  lightninglink
//
//  Created by William Casarin on 2022-03-25.
//

import SwiftUI
import Combine

enum BTCDenomination: String {
    case sats
    case bits
    case mbtc
    case btc
}

enum Denomination: CustomStringConvertible, Identifiable, Hashable {
    case fiat(Currency)
    case bitcoin(BTCDenomination)

    var description: String {
        switch self {
        case .fiat(let cur):
            return cur.rawValue
        case .bitcoin(let btc):
            return btc.rawValue
        }
    }

    var id: String {
        return self.description
    }
}

func get_preferred_denominations() -> [Denomination] {
    let fiat_pref_str = UserDefaults.standard.string(forKey: "fiat_denomination") ?? "USD"
    let btc_pref_str = UserDefaults.standard.string(forKey: "btc_denomination") ?? "sats"

    let btc_pref = BTCDenomination(rawValue: btc_pref_str) ?? .sats
    let fiat_pref = Currency(rawValue: fiat_pref_str) ?? .USD

    return [.bitcoin(btc_pref), .fiat(fiat_pref)]
}

struct AmountInput: View {
    @State var amount_msat: Int64? = nil
    let text: Binding<String>
    let rate: ExchangeRate?
    let onReceive: (String) -> Int64?

    var body: some View {
        VStack {
            Form {
                HStack(alignment: .lastTextBaseline) {
                    TextField("10,000", text: self.text)
                        .font(.title)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onReceive(Just(self.text)) {
                            amount_msat = onReceive($0.wrappedValue)
                        }
                    Text("sats")
                }
            }
            .frame(height: 100)

            if let msats = amount_msat {
                if let rate = self.rate {
                    Text("about \(sats_to_fiat(msats: msats, xr: rate))")
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

func sats_to_fiat(msats: Int64, xr: ExchangeRate) -> String {
    let btc = Double(msats) / Double(100_000_000_000)
    let rate = xr.rate * btc
    return String(format: "%.2f \(xr.currency)", rate)
}


