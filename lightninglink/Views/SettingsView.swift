//
//  SettingsView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-03-05.
//

import SwiftUI



struct SettingsView: View {
    @State var is_reset: Bool = false
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    func main_view() -> some View {
        VStack {
            HStack {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
            }

            Form {
                Section(header: Text("Connection settings")) {
                    Button("Disconnect LNLink") {
                        reset_lnlink()
                        self.presentationMode.wrappedValue.dismiss()
                        NotificationCenter.default.post(name: .reset, object: ())
                    }
                }

                Section(header: Text("Support")) {
                    Button("Buy me a 🍺") {
                        self.presentationMode.wrappedValue.dismiss()
                        NotificationCenter.default.post(name: .donate, object: ())
                    }
                }

            }
            .frame(height: 200)

            Spacer()
        }
        .padding()
    }

    var body: some View {
        if is_reset {
            SetupView()
        } else {
            main_view()
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
