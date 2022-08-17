//
//  RPC.swift
//  lightninglink
//
//  Created by William Casarin on 2022-01-30.
//

import Foundation
import SwiftUI


public typealias RequestRes<T> = Result<T, RequestError<RpcErrorData>>

public struct ResultWrapper<T: Decodable>: Decodable {
    public var result: T
}

public struct ErrorWrapper<T: Decodable>: Decodable {
    public var error: T
}

public struct RpcErrorData: Decodable, CustomStringConvertible {
    public var message: String

    public var description: String {
        return message
    }
}

public struct Output: Decodable {
    //public var txid: String
    //public var output: Int
    public var value: Int64
    //public var amount_msat: String
    //public var scriptpubkey: String
    //public var address: String
    //public var status: String
    //public var blockheight: Int
    //public var reserved: Bool
}

public struct Channel: Decodable {
    //public var peer_id: String
    //public var connected: Bool
    //public var state: String
    public var our_amount_msat: Int64
    public var amount_msat: Int64
}

public struct InvoiceRes: Decodable {
    public let bolt11: String
}

public struct OfferRes: Decodable {
    public let bolt12: String
}

public struct LNUrlPayDecode {
    public let description: String?
    public let longDescription: String?
    public let thumbnail: Image?
    public let vendor: String
}

public enum Decode {
    case invoice(InvoiceDecode)
    case lnurlp(LNUrlPayDecode)

    func thumbnail() -> Image? {
        switch self {
        case .lnurlp(let decode):
            return decode.thumbnail
        case .invoice:
            return nil
        }
    }

    func description() -> String? {
        switch self {
        case .invoice(let inv):
            return inv.description
        case .lnurlp(let lnurl):
            return lnurl.description
        }
    }

    func vendor() -> String? {
        switch self {
        case .invoice(let inv):
            return inv.vendor
        case .lnurlp(let lnurl):
            return lnurl.vendor
        }
    }

    func amount_msat() -> Int64? {
        switch self {
        case .invoice(let inv):
            return inv.amount_msat
        case .lnurlp:
            return nil
        }
    }
}

public struct InvoiceDecode: Decodable {
    public var type: String
    public var currency: String?
    public var valid: Bool
    public var created_at: Int64?
    public var expiry: Int64?
    public var relative_expiry: Int64?
    public var payee: String?
    public var quantity_min: Int?
    public var description: String?
    public var node_id: String?
    public var amount_msat: Int64?
    public var vendor: String?
}

func get_decode_expiry(_ decode: InvoiceDecode) -> Int64? {
    // bolt11
    if decode.expiry != nil {
        return decode.expiry
    }

    // bolt12
    return decode.relative_expiry
}

public struct FetchInvoice: Decodable {
    public var invoice: String
}

public struct ListFunds: Decodable {
    public var outputs: [Output]?
    public var channels: [Channel]?

    public static var empty = ListFunds(outputs: [], channels: [])
}

public struct MakeSecret: Decodable {
    public let secret: String
}

public struct Pay: Decodable {
    public var destination: String
    public var payment_hash: String
    public var created_at: Float
    public var parts: Int
    public var amount_msat: Int64
    public var amount_sent_msat: Int64
    public var payment_preimage: String
    public var status: String
}

public struct GetInfo: Decodable {
    public var alias: String
    public var id: String
    public var color: String
    public var network: String
    public var num_peers: Int
    public var fees_collected_msat: Int
    public var num_active_channels: Int
    public var blockheight: Int

    public static var empty = GetInfo(alias: "", id: "", color: "", network: "", num_peers: 0, fees_collected_msat: 0, num_active_channels: 0, blockheight: 0)
}

public enum RequestErrorType: Error {
    case decoding(DecodingError)
    case connectionFailed
    case initFailed
    case writeFailed
    case timeout
    case selectFailed
    case recvFailed
    case badCommandoMsgType(Int)
    case badConnectionString
    case outOfMemory
    case encoding(EncodingError)
    case status(Int)
    case unknown(String)
}

public struct RequestError<E: CustomStringConvertible & Decodable>: Error, CustomStringConvertible {
    public var response: HTTPURLResponse?
    public var respData: Data = Data()
    public var decoded: Either<String, E>?
    public var errorType: RequestErrorType

    init(errorType: RequestErrorType) {
        self.errorType = errorType
    }

    init(respData: Data, errorType: RequestErrorType) {
        self.respData = respData
        self.errorType = errorType
        self.decoded = maybe_decode_error_json(respData)
    }

    public var description: String {
        if let decoded = self.decoded {
            switch decoded {
            case .left(let err):
                return err
            case .right(let err):
                return err.description
            }
        }

        let strData = String(decoding: respData, as: UTF8.self)

        guard let resp = response else {
            return "respData: \(strData)\nerrorType: \(errorType)\n"
        }

        return "response: \(resp)\nrespData: \(strData)\nerrorType: \(errorType)\n"
    }
}


func parse_connection_string(_ cs: String) -> (String, String)? {
    let arr = cs.components(separatedBy: "@")
    if arr.count != 2 {
        return nil
    }
    return (arr[0], arr[1])
}

public func performRpcOnce<IN: Encodable, OUT: Decodable>(
    connectionString: String, operation: String, authToken: String,
    timeout_ms: Int32,
    params: IN
) -> RequestRes<OUT> {
    guard let parts = parse_connection_string(connectionString) else {
        return .failure(RequestError(errorType: .badConnectionString))
    }

    let node_id = parts.0
    let host = parts.1

    let ln = LNSocket()
    ln.genkey()

    guard ln.connect_and_init(node_id: node_id, host: host) else {
        return .failure(RequestError(errorType: .connectionFailed))
    }

    return performRpc(ln: ln, operation: operation, authToken: authToken, timeout_ms: timeout_ms, params: params)
}

public func performRpc<IN: Encodable, OUT: Decodable>(
    ln: LNSocket, operation: String, authToken: String, timeout_ms: Int32, params: IN) -> RequestRes<OUT>
{

    guard let msg = make_commando_msg(authToken: authToken, operation: operation, params: params) else {
        return .failure(RequestError(errorType: .outOfMemory))
    }

    guard ln.write(msg) else {
        return .failure(RequestError(errorType: .writeFailed))
    }

    switch commando_read_all(ln: ln, timeout_ms: timeout_ms) {
    case .failure(let req_err):
        return .failure(req_err)

    case .success(let data):
        return decodeJSON(data)
    }
}

func decodeJSON<T: Decodable>(_ dat: Data) -> RequestRes<T> {
    do {
        let dat = try JSONDecoder().decode(ResultWrapper<T>.self, from: dat)
        return .success(dat.result)
    }
    catch let decode_err as DecodingError {
        return .failure(RequestError(respData: dat, errorType: .decoding(decode_err)))
    }
    catch let err {
        return .failure(RequestError(respData: dat, errorType: .unknown("\(err)")))
    }
}


func make_commando_msg<IN: Encodable>(authToken: String, operation: String, params: IN) -> Data? {
    let encoder = JSONEncoder()
    let json_data = try! encoder.encode(params)
    guard let params_json = String(data: json_data, encoding: String.Encoding.utf8) else {
        return nil
    }
    var buf = [UInt8](repeating: 0, count: 65536)
    var outlen: Int32 = 0

    authToken.withCString { token in
    operation.withCString { op in
    params_json.withCString { ps in
        outlen = commando_make_rpc_msg(op, ps, token, 1, &buf, Int32(buf.capacity))
    }}}

    guard outlen != 0 else {
        return nil
    }

    return Data(buf[..<Int(outlen)])
}


func commando_read_all(ln: LNSocket, timeout_ms: Int32 = 2000) -> RequestRes<Data> {
    var rv: Int32 = 0
    var set = fd_set()
    var timeout = timeval()

    timeout.tv_sec = __darwin_time_t(timeout_ms / 1000);
    timeout.tv_usec = (timeout_ms % 1000) * 1000;

    fd_do_zero(&set)
    let fd = ln.fd()
    fd_do_set(fd, &set)

    var all_data = Data()

    while(true) {
        rv = select(fd + 1, &set, nil, nil, &timeout)

        if rv == -1 {
            return .failure(RequestError(errorType: .selectFailed))
        } else if rv == 0 {
            return .failure(RequestError(errorType: .timeout))
        }

        guard let (msgtype, data) = ln.recv() else {
            return .failure(RequestError(errorType: .recvFailed))
        }

        if msgtype == COMMANDO_REPLY_TERM {
            all_data.append(data[8...])
            break
        } else if msgtype == COMMANDO_REPLY_CONTINUES {
            all_data.append(data[8...])
            continue
        } else if msgtype == WIRE_PING.rawValue {
            // respond to pings for long requests like waitinvoice, etc
            ln.pong(ping: data)
        } else {
            //return .failure(RequestError(errorType: .badCommandoMsgType(Int(msgtype))))
            // we could get random messages like channel update! just ignore them
            continue
        }
    }

    return .success(all_data)
}

public let default_timeout: Int32 = 8000

public func rpc_getinfo(ln: LNSocket, token: String, timeout: Int32 = default_timeout) -> RequestRes<GetInfo>
{
    let params: Array<String> = []
    return performRpc(ln: ln, operation: "getinfo", authToken: token, timeout_ms: default_timeout, params: params)
}

public func rpc_offer(ln: LNSocket, token: String, amount: InvoiceAmount = .any, description: String? = nil, issuer: String? = nil) -> RequestRes<OfferRes> {

    let now = Date().timeIntervalSince1970
    let label = "lnlink-\(now)"
    let desc = description ?? "lnlink offer"
    var params: [String: String] = ["description": desc, "label": label]

    if let issuer = issuer {
        params["issuer"] = issuer
    }

    switch amount {
    case .amount(let val):
        params["amount"] = "\(val)msat"
    case .any:
        params["amount"] = "any"
    case .min(let val):
        params["amount"] = "\(val)msat"
    case .range(let min, _):
        params["amount"] = "\(min)msat"
    }

    return performRpc(ln: ln, operation: "offer", authToken: token, timeout_ms: default_timeout, params: params)
}

public func rpc_invoice(ln: LNSocket, token: String, amount: InvoiceAmount = .any, description: String? = nil, expiry: UInt64? = nil) -> RequestRes<InvoiceRes> {

    let now = Date().timeIntervalSince1970
    let label = "lnlink-\(now)"
    let desc = description ?? "lnlink invoice"
    var params: [String: String] = ["description": desc, "label": label]

    if let exp = expiry {
        params["expiry"] = "\(exp)"
    }

    switch amount {
    case .amount(let val):
        params["amount_msat"] = "\(val)msat"
    case .any:
        params["amount_msat"] = "any"
    case .min(let val):
        params["amount_msat"] = "\(val)msat"
    case .range(let min, _):
        params["amount_msat"] = "\(min)msat"
    }

    return performRpc(ln: ln, operation: "invoice", authToken: token, timeout_ms: default_timeout, params: params)
}

public func rpc_pay(ln: LNSocket, token: String, bolt11: String, amount_msat: Int64?, timeout_ms: Int32, description: String?) -> RequestRes<Pay>
{
    var params: [String: String] = ["bolt11": bolt11]
    if amount_msat != nil {
        params["amount_msat"] = "\(amount_msat!)"
    }
    
    if let desc = description {
        params["description"] = desc
    }
    
    return performRpc(ln: ln, operation: "pay", authToken: token, timeout_ms: timeout_ms, params: params)
}

public func rpc_listfunds(ln: LNSocket, token: String) -> RequestRes<ListFunds>
{
    let params: Array<String> = []
    return performRpc(ln: ln, operation: "listfunds", authToken: token, timeout_ms: default_timeout, params: params)
}

public func rpc_makesecret(ln: LNSocket, token: String, hex: String) -> RequestRes<MakeSecret>
{
    let params: Array<String> = [hex]
    return performRpc(ln: ln, operation: "makesecret", authToken: token, timeout_ms: 1000, params: params)
}

public func rpc_decode(ln: LNSocket, token: String, inv: String) -> RequestRes<InvoiceDecode>
{
    let params = [ inv ];
    return performRpc(ln: ln, operation: "decode", authToken: token, timeout_ms: 1000, params: params)
}

public func rpc_fetchinvoice(ln: LNSocket, token: String, req: FetchInvoiceReq) -> RequestRes<FetchInvoice>
{
    var params: [String: String] = [ "offer": req.offer ]

    if let pay_amt = req.pay_amt {
        let amt = pay_amt.amount + (pay_amt.tip ?? 0)
        params["amount_msat"] = "\(amt)msat"
    }

    let timeout = req.timeout ?? 15
    params["timeout"] = "\(timeout)"

    if let qty = req.quantity {
        params["quantity"] = "\(qty)"
    }

    return performRpc(ln: ln, operation: "fetchinvoice", authToken: token, timeout_ms: Int32((timeout + 2) * 1000), params: params)
}

public func maybe_decode_error_json<T: Decodable>(_ dat: Data) -> Either<String, T>? {
    do {
        return .right(try JSONDecoder().decode(ErrorWrapper<T>.self, from: dat).error)
    } catch {
        do {
            return .left(try JSONDecoder().decode(ErrorWrapper<String>.self, from: dat).error)
        } catch {
            return nil
        }
    }
}
