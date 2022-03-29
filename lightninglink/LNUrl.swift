//
//  LNUrl.swift
//  lightninglink
//
//  Created by William Casarin on 2022-03-12.
//

import Foundation
import SwiftUI

public struct LNUrlDecode {
    let encoded: Bech32
}

public enum Bech32Type {
    case bech32
    case bech32m
}

public struct LNUrlError: Decodable {
    let status: String?
    let reason: String?

    public init (reason: String) {
        self.status = "ERROR"
        self.reason = reason
    }
}

public struct LNUrlPay: Decodable {
    let callback: URL
    let maxSendable: UInt64?
    let minSendable: UInt64?
    let metadata: String
    let tag: String
}

public struct LNUrlPayInvoice: Decodable {
    let pr: String
}

public enum LNUrl {
    case payRequest(LNUrlPay)
}

public struct Bech32 {
    let hrp: String
    let dat: Data
    let type: Bech32Type
}

func decode_bech32(_ str: String) -> Bech32? {
    let hrp_buf = UnsafeMutableBufferPointer<CChar>.allocate(capacity: str.count)
    let bits_buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: str.count)
    let data_buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: str.count)
    var bitslen: Int = 0
    var datalen: Int = 0
    var m_hrp_str: String? = nil
    var m_data: Data? = nil
    var typ: bech32_encoding = BECH32_ENCODING_NONE

    hrp_buf.withMemoryRebound(to: CChar.self) { hrp_ptr in
    str.withCString { input in
        typ = bech32_decode(hrp_ptr.baseAddress, bits_buf.baseAddress, &bitslen, input, str.count)
        bech32_convert_bits(data_buf.baseAddress, &datalen, 8, bits_buf.baseAddress, bitslen, 5, 0)
        if datalen == 0 {
            return
        }
        m_data = Data(buffer: data_buf)[...(datalen-1)]
        m_hrp_str = String(cString: hrp_ptr.baseAddress!)
    }
    }

    guard let hrp = m_hrp_str else {
        return nil
    }

    guard let data = m_data else {
        return nil
    }

    var m_type: Bech32Type? = nil
    if typ == BECH32_ENCODING_BECH32 {
        m_type = .bech32
    } else if typ == BECH32_ENCODING_BECH32M {
        m_type = .bech32m
    }

    guard let type = m_type else {
        return nil
    }

    return Bech32(hrp: hrp, dat: data, type: type)
}

func decode_lnurl(_ data: Data) -> LNUrl? {
    let lnurlp: LNUrlPay? = decode_data(data)
    return lnurlp.map { .payRequest($0) }
}

func decode_lnurl_pay(_ data: Data) -> LNUrlPayInvoice? {
    return decode_data(data)
}

func decode_data<T: Decodable>(_ data: Data) -> T? {
    let decoder = JSONDecoder()
    do {
        return try decoder.decode(T.self, from: data)
    } catch {
        print("decode_data failed for \(T.self): \(error)")
    }

    return nil
}

func lnurl_fetchinvoice(lnurlp: LNUrlPay, amount: Int64, completion: @escaping (Either<LNUrlError, LNUrlPayInvoice>) -> ()) {
    let c = lnurlp.callback.absoluteString.contains("?") ? "&" : "?"
    guard let url = URL(string: lnurlp.callback.absoluteString + "\(c)amount=\(amount)") else {
        completion(.left(LNUrlError(reason: "Invalid lnurl callback")))
        return
    }
    handle_lnurl_request(url, completion: completion)
}

func handle_lnurl_request<T: Decodable>(_ url: URL, completion: @escaping (Either<LNUrlError, T>) -> ()) {
    let task = URLSession.shared.dataTask(with: url) { (mdata, response, error) in
        guard let data = mdata else {
            completion(.left(LNUrlError(reason: "Request failed: \(error.debugDescription)")))
            return
        }

        if let merr: LNUrlError = decode_data(data) {
            if merr.status == "ERROR" {
                completion(.left(merr))
            }
        }

        guard let t: T = decode_data(data) else {
            completion(.left(LNUrlError(reason: "Failed when decoding \(T.self)")))
            return
        }

        completion(.right(t))
    }

    task.resume()
}

func handle_lnurl(_ url: URL, completion: @escaping (LNUrl?) -> ()) {
    let task = URLSession.shared.dataTask(with: url) { (mdata, response, error) in
        guard let data = mdata else {
            let lnurl: LNUrl? = nil
            completion(lnurl)
            return
        }

        completion(decode_lnurl(data))
    }

    task.resume()
}


func decode_lnurlp_metadata(_ lnurlp: LNUrlPay) -> LNUrlPayDecode {
    var metadata = Array<Array<String>>()
    do {
        metadata = try JSONDecoder().decode(Array<Array<String>>.self, from: Data(lnurlp.metadata.utf8))
    } catch {

    }

    var description: String? = nil
    var longDescription: String? = nil
    var thumbnail: Image? = nil
    var vendor: String = lnurlp.callback.host ?? ""

    for entry in metadata {
        if entry.count == 2 {
            if entry[0] == "text/plain" {
                description = entry[1]
            } else if entry[0] == "text/identifier" {
                vendor = entry[1]
            } else if entry[0] == "text/long-desc" {
                longDescription = entry[1]
            } else if entry[0] == "image/png;base64" || entry[0] == "image/jpg;base64" {
                guard let dat = Data(base64Encoded: entry[1]) else {
                    continue
                }
                guard let ui_img = UIImage(data: dat) else {
                    continue
                }
                thumbnail = Image(uiImage: ui_img)
            }
        }
    }

    return LNUrlPayDecode(description: description, longDescription: longDescription, thumbnail:    thumbnail, vendor: vendor)
}
