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

struct ParsedAmount {
    let msats_str: String?
    let msats: Int64?

    static var empty: ParsedAmount {
        ParsedAmount(msats_str: nil, msats: nil)
    }
}

struct AmountInput: View {
    @State var amount_msat: Int64? = nil
    let text: Binding<String>
    let placeholder: String
    let onReceive: (ParsedAmount) -> ()

    var body: some View {
        VStack {
            HStack(alignment: .lastTextBaseline) {
                TextField(placeholder, text: self.text)
                    .font(.title)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .onReceive(Just(self.text)) {
                        onReceive(parse_msat_input($0.wrappedValue))
                    }
                Text("sats")
            }

        }
    }
}


func msats_to_fiat(msats: Int64, xr: ExchangeRate) -> String {
    let btc = Double(msats) / Double(100_000_000_000)
    let rate = xr.rate * btc
    let num_fmt = NumberFormatter()
    num_fmt.numberStyle = .decimal
    let fmt = num_fmt.string(from: NSNumber(value: round(rate * 100) / 100.0))!
    return "$\(fmt)"
}


func parse_msat_input(_ new_val: String) -> ParsedAmount {
    if new_val == "" {
        return ParsedAmount(msats_str: "", msats: nil)
    }

    let ok = new_val.allSatisfy { $0 == "," || ($0 >= "0" && $0 <= "9") }
    if ok {
        let num_fmt = NumberFormatter()
        num_fmt.numberStyle = .decimal

        let filtered = new_val.filter { $0 >= "0" && $0 <= "9" }
        let sats = Int64(filtered) ?? 0
        let msats = sats * 1000
        let ret = num_fmt.string(from: NSNumber(value: sats)) ?? new_val
        return ParsedAmount(msats_str: ret, msats: msats)
    }

    return .empty
}

