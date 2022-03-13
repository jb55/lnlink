//
//  QR.swift
//  lightninglink
//
//  Created by William Casarin on 2022-03-12.
//

import Foundation


public enum LNScanResult {
    case lightning(DecodeType)
    case lnlink(LNLink)
    case lnurl(URL)
}


func handle_qrcode(_ qr: String) -> Either<String, LNScanResult> {
    let invstr = qr.trimmingCharacters(in: .whitespacesAndNewlines)
    var lowered = invstr.lowercased()

    if lowered.starts(with: "lightning:") {
        let index = invstr.index(invstr.startIndex, offsetBy: 10)
        lowered = String(lowered[index...])
    }

    if lowered.starts(with: "lnlink:") {
        switch parse_auth_qr(invstr) {
        case .left(let err):
            return .left(err)
        case .right(let lnlink):
            return .right(.lnlink(lnlink))
        }
    }

    if lowered.starts(with: "lnurl") {
        guard let bech32 = decode_bech32(lowered) else {
            return .left("Invalid lnurl bech32 encoding")
        }

        let url = String(decoding: bech32.dat, as: UTF8.self)
        if let email = parse_email(str: url) {
            guard let lnurl = make_lnaddress(email: email) else {
                return .left("Couldn't make lnaddress from email")
            }
            return .right(.lnurl(lnurl))
        }

        guard let lnurl = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .left("Couldn't make lnurl from qr")
        }

        return .right(.lnurl(lnurl))
    }

    if let email = parse_email(str: lowered) {
        guard let lnurl = make_lnaddress(email: email) else {
            return .left("Couldn't make lnaddress from email")
        }
        return .right(.lnurl(lnurl))
    }

    guard let parsed = parseInvoiceString(invstr) else {
        return .left("Failed to parse invoice")
    }

    return .right(.lightning(parsed))
}


struct Email {
    let name: String
    let host: String
}

func parse_email(str: String) -> Email? {
    let parts = str.split(separator: "@")

    guard parts.count == 2 else {
        return nil
    }

    if parts[0].contains(":") {
        return nil
    }

    if !parts[1].contains(".") {
        return nil
    }

    let name = String(parts[0])
    let host = String(parts[1])

    return Email(name: name, host: host)
}


func make_lnaddress(email: Email) -> URL? {
    return URL(string: "https://\(email.host)/.well-known/lnurlp/\(email.name)")
}
