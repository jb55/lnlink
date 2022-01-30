//
//  RPC.swift
//  lightninglink
//
//  Created by William Casarin on 2022-01-30.
//

import Foundation


public typealias RequestRes<T> = Result<T, RequestError>

public struct ResultWrapper<T: Decodable>: Decodable {
    public var result: T
}

public struct GetInfo: Decodable {
    public var alias: String
    public var id: String
    public var color: String
    public var network: String
    public var num_peers: Int
    public var msatoshi_fees_collected: Int
    public var num_active_channels: Int

    public static var empty = GetInfo(alias: "", id: "", color: "", network: "", num_peers: 0, msatoshi_fees_collected: 0, num_active_channels: 0)
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

public struct RequestError: Error, CustomStringConvertible {
    public var response: HTTPURLResponse?
    public var respData: Data = Data()
    public var errorType: RequestErrorType

    init(errorType: RequestErrorType) {
        self.errorType = errorType
    }

    init(respData: Data, errorType: RequestErrorType) {
        self.respData = respData
        self.errorType = errorType
    }

    public var description: String {
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
    params: IN
) -> RequestRes<OUT> {
    guard let parts = parse_connection_string(connectionString) else {
        return .failure(RequestError(errorType: .badConnectionString))
    }

    let node_id = parts.0
    let host = parts.1

    let ln = LNSocket()
    ln.genkey()

    guard ln.connect(node_id: node_id, host: host) else {
        return .failure(RequestError(errorType: .connectionFailed))
    }

    guard ln.perform_init() else {
        return .failure(RequestError(errorType: .initFailed))
    }

    return performRpc(ln: ln, operation: operation, authToken: authToken, params: params)
}

public func performRpc<IN: Encodable, OUT: Decodable>(
    ln: LNSocket, operation: String, authToken: String, params: IN) -> RequestRes<OUT>
{

    guard let msg = make_commando_msg(authToken: authToken, operation: operation, params: params) else {
        return .failure(RequestError(errorType: .outOfMemory))
    }

    guard ln.write(msg) else {
        return .failure(RequestError(errorType: .writeFailed))
    }

    switch commando_read_all(ln: ln) {
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
    var outlen: UInt16 = 0
    var ok: Bool = false

    authToken.withCString { token in
    operation.withCString { op in
    params_json.withCString { ps in
        ok = commando_make_rpc_msg(op, ps, token, 1, &buf, Int32(buf.capacity), &outlen) != 0
    }}}

    guard ok else {
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

        all_data.append(data[8...])

        if msgtype == COMMANDO_REPLY_TERM {
            break
        } else if msgtype == COMMANDO_REPLY_CONTINUES {
            continue
        } else {
            return .failure(RequestError(errorType: .badCommandoMsgType(Int(msgtype))))
        }
    }

    return .success(all_data)
}


public func rpc_getinfo(ln: LNSocket, token: String) -> RequestRes<GetInfo>
{
    let params: Array<String> = []
    return performRpc(ln: ln, operation: "getinfo", authToken: token, params: params)
}
