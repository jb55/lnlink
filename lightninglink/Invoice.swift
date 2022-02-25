//
//  Invoice.swift
//  lightninglink
//
//  Created by William Casarin on 2022-02-05.
//

import Foundation


public enum InvoiceAmount {
    case amount(Int64)
    case any
}

// this is just a quick stopgap before we have full invoice parsing
public func parseInvoiceAmount(_ invoice: String) -> InvoiceAmount?
{
    let inv = invoice.lowercased()

    if !inv.starts(with: "lnbc") {
        return nil
    }

    var ind = 4
    var num: String = ""
    var scale: Character = Character("p")
    var sep: Character

    // number part
    while true {
        let c = inv[inv.index(inv.startIndex, offsetBy: ind)]
        ind += 1

        if c >= "0" && c <= "9" {
            continue
        } else {
            let start_ind = inv.index(inv.startIndex, offsetBy: 4)
            let end_ind = inv.index(inv.startIndex, offsetBy: ind - 1)

            scale = inv[inv.index(inv.startIndex, offsetBy: ind - 1)]
            sep = inv[inv.index(inv.startIndex, offsetBy: ind)]
            num = String(inv[start_ind..<end_ind])

            if sep != "1" {
                return .any
            }

            break
        }
    }

    if !(scale == "m" || scale == "u" || scale == "n" || scale == "p") {
        return nil
    }

    guard let n = Int(num) else {
        return nil
    }

    switch scale {
    case "m": return .amount(Int64(n * 100000000));
    case "u": return .amount(Int64(n * 100000));
    case "n": return .amount(Int64(n * 100));
    case "p": return .amount(Int64(n * 1));
    default: return nil
    }
}

/*
public func parseInvoice(_ str: String) -> Invoice?
{
    // decode bech32

    do {
        let (hrp, _) = try decodeBech32(bechString: str)

        let hrp_data = Data(hrp)
        let hrp_str = String(data: hrp_data, encoding: .utf8)!
        print(hrp_str)

    } catch {
        print("parseInvoice: unexpected error \(error)")
        return nil
    }

    return .bolt11(Bolt11Invoice(msats: 100000))
}


public func invoiceAmount(_ inv: Invoice) -> Int64
{
    switch (inv) {
    case .bolt11(let b11):
        return b11.msats
    case .bolt12(let b12):
        return b12.msats
    }

}
 */
