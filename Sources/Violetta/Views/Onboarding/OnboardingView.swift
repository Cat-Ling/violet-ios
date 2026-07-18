import SwiftUI

struct OnboardingView: View {
    @AppStorage("serverURL") private var serverURL: String = ""
    @State private var inputURL: String = ""
    @State private var isTestingConnection = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "server.rack")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.violetPrimary)
                
                Text("Welcome to Violetta")
                    .font(.largeTitle.bold())
                
                Text("Please enter your Violet Server address to connect. Usually this looks like http://192.168.1.100:3001.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                TextField("http://...", text: $inputURL)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal)
                
                Button {
                    testAndSaveConnection()
                } label: {
                    if isTestingConnection {
                        ProgressView()
                    } else {
                        Text("Connect")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.violetPrimary)
                .padding(.horizontal)
                .disabled(inputURL.isEmpty || isTestingConnection)
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func testAndSaveConnection() {
        // Placeholder for real connection test
        var cleanURL = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanURL.hasSuffix("/") {
            cleanURL.removeLast()
        }
        if !cleanURL.hasPrefix("http") {
            cleanURL = "http://" + cleanURL
        }
        
        serverURL = cleanURL
    }
}
