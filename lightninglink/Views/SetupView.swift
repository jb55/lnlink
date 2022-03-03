//
//  SetupView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-02-26.
//

import SwiftUI
import Foundation

public enum ActiveAuthSheet: Identifiable {
    public var id: String {
        switch self {
        case .qr:
            return "qrcode"
        }
    }

    case qr
}

public enum SetupResult {
    case connection_failed
    case plugin_missing
    case auth_invalid(String)
    case success(GetInfo, ListFunds)
}

public enum SetupViewState {
    case initial
    case validating(LNLink)
    case validated
}

func initial_state() -> SetupViewState {
    let lnlink = load_lnlink()
    if lnlink != nil {
        return .validating(lnlink!)
    }

    return .initial
}

struct SetupView: View {
    @State var active_sheet: ActiveAuthSheet? = nil
    @State var state: SetupViewState = initial_state()
    @State var error: String? = nil
    @State var dashboard: Dashboard = .empty
    @State var lnlink: LNLink? = nil

    func perform_validation(_ lnlink: LNLink) {
        DispatchQueue.global(qos: .background).async {
            validate_connection(lnlink: lnlink) { res in
                switch res {
                case .connection_failed:
                    self.state = .initial
                    self.error = "Connection failed"
                case .plugin_missing:
                    self.state = .initial
                    self.error = "Connected but could not retrieve data. Commando plugin missing?"
                case .auth_invalid(let str):
                    self.state = .initial
                    self.error = str
                case .success(let info, let funds):
                    save_lnlink(lnlink: lnlink)
                    self.lnlink = lnlink
                    self.dashboard = Dashboard(info: info, funds: funds)
                    self.state = .validated
                    self.error = nil
                }
            }
        }
    }

    func setup_view() -> some View {
        VStack {
            Text("Connect")
                .font(.headline)

            Spacer()

            Button("Scan LNLink QR Code") {
                self.active_sheet = .qr
            }
            .foregroundColor(Color.blue)
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)

            if self.error != nil {
                Text("Error: \(self.error!)")
                    .foregroundColor(Color.red)
            }

            Spacer()

            Link("What the heck is LNLink?", destination: URL(string:"http://lnlink.app/qr")!)
        }
        .padding()
        .sheet(item: $active_sheet) { active_sheet in
            switch active_sheet {
            case .qr:
                CodeScannerView(codeTypes: SCAN_TYPES) { code_res in
                    switch code_res {
                    case .success(let scan_res):
                        let auth_qr = scan_res.string
                        // auth_qr ~ lnlink:host:port?nodeid=nodeid&token=rune
                        let m_lnlink = parse_auth_qr(auth_qr)

                        switch m_lnlink {
                        case .left(let err):
                            self.error = err
                        case .right(let lnlink):
                            self.state = .validating(lnlink)
                        }

                    case .failure(let scan_err):
                        self.error = scan_err.localizedDescription
                    }
                }
            }
        }

    }

    func validating_view(lnlink: LNLink) -> some View {
        Text("Connecting...")
            .onAppear() {
                self.perform_validation(lnlink)
            }
    }

    var body: some View {
        Group {
            switch self.state {
            case .initial:
                setup_view()
            case .validating(let lnlink):
                validating_view(lnlink: lnlink)
            case .validated:
                ContentView(dashboard: self.dashboard, lnlink: self.lnlink!)
            }
        }
    }
}

struct SetupView_Previews: PreviewProvider {
    static var previews: some View {
        SetupView()
    }
}


func get_qs_param(qs: URLComponents, param: String) -> String? {
    return qs.queryItems?.first(where: { $0.name == param })?.value
}


func parse_auth_qr(_ qr: String) -> Either<String, LNLink> {
    var auth_qr = qr
    if auth_qr.hasPrefix("lnlink:") && !auth_qr.hasPrefix("lnlink://") {
        auth_qr = qr.replacingOccurrences(of: "lnlink:", with: "lnlink://")
    }

    guard let url = URL(string: auth_qr) else {
        return .left("Invalid url")
    }

    guard let nodeid = url.user else {
        return .left("No nodeid found in auth qr")
    }

    guard var host = url.host else {
        return .left("No hostname found in auth qr")
    }

    let port = url.port ?? 9735
    host = host + ":\(port)"

    guard let qs = URLComponents(string: auth_qr) else {
        return .left("Invalid url querystring")
    }

    guard let token = get_qs_param(qs: qs, param: "token") else {
        return .left("No token found in auth qr")
    }

    let lnlink = LNLink(token: token, host: host, node_id: nodeid)
    return .right(lnlink)
}


func validate_connection(lnlink: LNLink, completion: @escaping (SetupResult) -> Void) {
    let ln = LNSocket()

    guard ln.connect_and_init(node_id: lnlink.node_id, host: lnlink.host) else {
        completion(.connection_failed)
        return
    }

    let res = rpc_getinfo(ln: ln, token: lnlink.token, timeout: 5000)

    switch res {
    case .failure(let rpc_err):
        switch rpc_err.errorType {
        case .timeout:
            completion(.plugin_missing)
            return
        default:
            break
        }

        completion(.auth_invalid(rpc_err.description))

    case .success(let getinfo):
        let funds_res = rpc_listfunds(ln: ln, token: lnlink.token)

        switch funds_res {
        case .failure(let err):
            print(err)
            completion(.success(getinfo, .empty))
        case .success(let listfunds):
            completion(.success(getinfo, listfunds))
        }
    }
}
