
import Foundation

public class LNSocket {
    var ln: OpaquePointer!

    init() {
        self.ln = lnsocket_create()
    }

    func genkey() {
        lnsocket_genkey(self.ln)
    }

    func testrun() -> GetInfo? {
        let node_id = "03f3c108ccd536b8526841f0a5c58212bb9e6584a1eb493080e7c1cc34f82dad71"
        let host = "24.84.152.187"

        self.genkey()

        guard self.connect(node_id: node_id, host: host) else {
            return nil
        }

        guard self.perform_init() else {
            return nil
        }

        let res = rpc_getinfo(ln: self, token: "")

        switch res {
        case .success(let getinfo):
            return getinfo

        case .failure(let err):
            print("\(err)")
            return nil
        }
    }

    func connect(node_id: String, host: String) -> Bool {
        node_id.withCString { p_node_id in
            host.withCString { p_host in
                return lnsocket_connect(self.ln, p_node_id, p_host) != 0
            }
        }
    }

    func write(_ data: Data) -> Bool {
        data.withUnsafeBytes { msg in
            return lnsocket_write(self.ln, msg, UInt16(data.count)) != 0
        }
    }

    func fd() -> Int32 {
        var sock: Int32 = 0
        lnsocket_fd(self.ln, &sock)
        return sock
    }

    func recv() -> (UInt16, Data)? {
        var msgtype: UInt16 = 0
        var mpayload = UnsafeMutablePointer<UInt8>(nil)
        var payload_len: UInt16 = 0

        guard lnsocket_recv(self.ln, &msgtype, &mpayload, &payload_len) != 0 else {
            return nil
        }

        guard let payload = mpayload else {
            return nil
        }

        let data = Data(bytes: payload, count: Int(payload_len))

        return (msgtype, data)
    }

    func perform_init() -> Bool {
        return lnsocket_perform_init(self.ln) != 0
    }

    func print_errors() {
        lnsocket_print_errors(self.ln)
    }

    deinit {
        lnsocket_destroy(self.ln)
    }
}
