//
//  Invoice.swift
//  lightninglink
//
//  Created by William Casarin on 2022-02-05.
//

import Foundation


public struct Bolt11Invoice {
    var msats: Int64
}

public struct Bolt12Invoice {
    var msats: Int64
}

public enum Invoice {
    case bolt11(Bolt11Invoice)
    case bolt12(Bolt12Invoice)

    func amount() -> Int64 {
        return invoiceAmount(self)
    }

    static var empty: Invoice {
        let b11 = Bolt11Invoice(msats: 0)
        let inv: Invoice = .bolt11(b11)
        return inv
    }
}

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
