import SwiftUI

@main
struct LinkGuardTLApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack {
                Text("LinkGuard-TL")
                    .font(.largeTitle)
                    .padding()
                Text("現場分區指揮系統")
                    .font(.headline)
                    .padding()
                NavigationLink(destination: ZoneCreationView()) {
                    Text("建立分區")
                        .font(.title2)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
    }
}

struct ZoneCreationView: View {
    @State private var zoneName: String = ""
    @State private var zones: [String] = []

    var body: some View {
        VStack {
            Text("建立分區")
                .font(.title)
                .padding()
            TextField("輸入分區名稱", text: $zoneName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            Button(action: {
                if !zoneName.isEmpty {
                    zones.append(zoneName)
                    zoneName = ""
                }
            }) {
                Text("新增分區")
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            List(zones, id: \ .self) { zone in
                Text(zone)
            }
        }
        .padding()
    }
}