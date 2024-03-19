import Foundation
import PipeableSDK
import SwiftUI
import WebKit

enum ResultStatus {
    case success
    case failure
}

struct AirBnBAgentWebView: View {
    @Binding var prompt: String
    var onClose: () -> Void
    var onResult: (ResultStatus) -> Void

    @State var working = false
    @State var done = false
    @State var statusText = ""
    @State var statusAnimated: Bool = false

    var body: some View {
        NavigationView {
            VStack {
                WebViewWrapper(prompt: prompt, onClose: onClose, onStatusChange: onStatusChange)
                    .allowsHitTesting(!working)
                    .ignoresSafeArea(edges: .bottom)
                StatusView(text: statusText, animated: statusAnimated, done: done, userControl: !working)
                    .frame(height: 60)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        // Action to dismiss the view
                        onClose()
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("airbnb.com")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Logout", action: {
                            deleteAllCookies()
                            onClose()
                        })
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }

    func onStatusChange(_ status: Status) {
        switch status {
        case .login:
            statusText = "👤  Logging in"
            statusAnimated = false
            working = false
        case .working(let action):
            statusText = "🤖 \(action)"
            statusAnimated = true
            working = true
        case .done:
            statusText = "👤 Done. Presenting your results"
            statusAnimated = false
            working = false
            done = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onResult(.success)
            }
        case .failure:
            statusText = "❌ Automation failed"
            statusAnimated = false
            working = false
            done = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onResult(.success)
            }
        }
    }
}

struct WebViewWrapper: UIViewControllerRepresentable {
    var prompt: String
    var onClose: () -> Void
    var onStatusChange: (_ status: Status) -> Void
    var initialized: Bool = false

    init(prompt: String, onClose: @escaping () -> Void, onStatusChange: @escaping (_ status: Status) -> Void) {
        self.prompt = prompt
        self.onClose = onClose
        self.onStatusChange = onStatusChange
    }

    func makeUIViewController(context _: UIViewControllerRepresentableContext<WebViewWrapper>) -> WKWebViewController {
        let uiViewController = WKWebViewController()
        uiViewController.onClose = onClose
        uiViewController.onStatusChange = onStatusChange
        uiViewController.prompt = prompt

        return uiViewController
    }

    func updateUIViewController(_ uiViewController: WKWebViewController, context _: UIViewControllerRepresentableContext<WebViewWrapper>) {
        if uiViewController.isStarted {
            return
        }

        Task {
            do {
                try await uiViewController.start()
            } catch {
                print("An unexpected error occurred: \(error)")
            }
        }
    }
}

class WKWebViewController: UIViewController {
    /*
     This class handles initializing the WKWebView and setting up the toolbar. Additionally,
     it handles initializing the PipeablePage, Agent, and AirBnBTools, and orchestrating the automation.
     */

    var webView: PipeableWebView!
    var prompt: String!
    var isStarted: Bool = false
    var onClose: (() -> Void)!
    var onStatusChange: ((_ status: Status) -> Void)!

    override func loadView() {
        view = UIView()

        webView = PipeableWebView(frame: view.frame)
        webView.configuration.applicationNameForUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3.1 Mobile/15E148 Safari/604.1"

        view.addSubview(webView)

        webView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // Handles orchestrating between the Agent, the PipeablePage, and the AirBnBTools
    func start() async throws {
        // No re-entry.
        isStarted = true

        let page = webView.page

        do {
            let airBnbTools = AirBnBTools(page: page)

            onStatusChange(.login)

            try await airBnbTools.login()

            onStatusChange(.working(action: "GPT thinking"))

            let agent = Agent(
                airBnBTools: airBnbTools,
                openAIAPIToken: "<OPENAI-KEY-HERE>",
                onStep: { stepName in self.onStatusChange(.working(action: stepName)) }
            )

            if prompt.isEmpty {
                return
            }

            var res = try await agent.step(message: prompt)

            print(res)

            while !res.done {
                try await Task.sleep(nanoseconds: 2000 * 1_000_000)
                res = try await agent.step(message: nil)
                print(res)
            }

        } catch {
            print("Error: \(error)")
            onStatusChange(.failure)
        }

        onStatusChange(.done)
    }
}

public func deleteAllCookies() {
    let dataStore = WKWebsiteDataStore.default()
    let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
    let dateFrom = Date(timeIntervalSince1970: 0)

    dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom, completionHandler: {})
}

struct AirBnBWebView_Previews: PreviewProvider {
    @State static var prompt: String = ""

    static var previews: some View {
        AirBnBAgentWebView(
            prompt: $prompt,
            onClose: {},
            onResult: { _ in }
        )
    }
}
