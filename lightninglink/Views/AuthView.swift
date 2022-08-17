//
//  AuthView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-08-08.
//

import SwiftUI
import CryptoKit
import CommonCrypto


struct AuthView: View {
    let auth: LNUrlAuth
    let lnlink: LNLink
    @State var error: String? = nil
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text(auth.url.host ?? "Unknown")
                .font(.largeTitle)
            
            Button(action: { login() }) {
                Text(auth.tag.capitalized)
                    .padding()
                    .font(.largeTitle)
            }
            .background {
                Color.accentColor
            }
            .foregroundColor(Color.white)
            .cornerRadius(20)
            
            if let error = error {
                Text(error)
                    .foregroundColor(Color.red)
                    .padding(20)
            }
        }
    }
    
    func login() {
        let ln = LNSocket()
        guard ln.connect_and_init(node_id: lnlink.node_id, host: lnlink.host) else {
            error = "Could not connect to node"
            return
        }
        guard let hex = make_secret_hex(self.auth) else {
            error = "Could not make secret"
            return
        }
        Task.init {
            let res = rpc_makesecret(ln: ln, token: lnlink.token, hex: hex)
            switch res {
            case .failure(let err):
                self.error = err.description
            case .success(let makesec):
                let sec = makesec.secret
                await do_login(sec, auth: self.auth)
            }
        }
    }
    
    func do_login(_ hexsec: String, auth: LNUrlAuth) async {
        var url_str = auth.url.absoluteString
        
        var dersig = Array<UInt8>.init(repeating: 0, count: 72)
        var pk = Array<UInt8>.init(repeating: 0, count: 33)
        var sig = secp256k1_ecdsa_signature()
        
        guard let sec = hex_decode(hexsec) else {
            self.error = "Could not hex decode secret key"
            return
        }
        
        guard var msg = hex_decode(auth.k1) else {
            self.error = "Could not decode k1 challenge string as hex: '\(auth.k1)'"
            return
        }
        
        
        let opts = UInt32(SECP256K1_CONTEXT_SIGN)
        guard let ctx = secp256k1_context_create(opts) else {
            return
        }
        
        var pubkey = secp256k1_pubkey()
        
        //let msg2 = sha256(msg)
        
        guard secp256k1_ecdsa_sign(ctx, &sig, msg, sec, nil, nil) == 1 else {
            self.error = "Failed to sign"
            return
        }
        
        var siglen: Int = 72
        guard secp256k1_ecdsa_signature_serialize_der(ctx, &dersig, &siglen, &sig) == 1 else {
            self.error = "Failed to encode DER ecdsa signature"
            return
        }
        
        dersig = Array(dersig[..<siglen])
        
        defer { secp256k1_context_destroy(ctx) }
        
        guard secp256k1_ec_pubkey_create(ctx, &pubkey, sec) == 1 else {
            self.error = "Failed to get pubkey from keypair"
            return
        }
        
        var pklen: Int = 33
        guard secp256k1_ec_pubkey_serialize(ctx, &pk, &pklen, &pubkey, UInt32(SECP256K1_EC_COMPRESSED)) == 1 else {
            self.error = "Failed to serialize pubkey"
            return
        }
        
        let hex_key = hex_encode(pk)
        let hex_sig = hex_encode(dersig)

        url_str += "&sig=" + hex_sig + "&key=" + hex_key
        
        guard let url = URL(string: url_str) else {
            self.error = "Invalid url: \(url_str)"
            return
        }
        
        // (data, resp)
        guard let (data, resp) = try? await URLSession.shared.data(from: url) else {
            self.error = "Login failed"
            return
        }
        
        print("\(resp)")
        print("\(data)")
        
        dismiss()
    }
    
}

func make_secret_hex(_ auth: LNUrlAuth) -> String? {
    guard let host_data = auth.host.data(using: .utf8) else {
        return nil
    }
    return hex_encode(Array(host_data))
}

struct AuthView_Previews: PreviewProvider {
    
    static var previews: some View {
        let auth = LNUrlAuth(k1: "k1", tag: "login", url: URL(string: "jb55.com")!, host: "jb55.com")
        let lnlink = LNLink(token: "", host: "", node_id: "")
        AuthView(auth: auth, lnlink: lnlink)
    }
}
        
func sha256(_ data: [UInt8]) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    var data = data
    CC_SHA256(&data, CC_LONG(data.count), &hash)
    return hash
}
