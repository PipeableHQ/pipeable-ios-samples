import Foundation
import PipeableSDK
import SwiftUI
import WebKit

enum ResultStatus {
    case success
    case failure
}

struct Pipeable_WebView: View {
    var onClose: () -> Void
    var onResult: (ResultStatus) -> Void

    @State var working = false
    @State var done = false
    @State var statusText = ""
    @State var statusAnimated: Bool = false

    var body: some View {
        ZStack {
            WebViewWrapper(onClose: onClose, onStatusChange: onStatusChange)
//                .blur(radius: working ? 1.0 : 0)
                .allowsHitTesting(!working)

            StatusView(text: statusText, animated: statusAnimated, done: done, userControl: !working)
//                .allowsHitTesting(working || done)
        }
    }

    func onStatusChange(_ status: Status) {
        if status == .login {
            statusText = "👤  Logging in"
            statusAnimated = false
            working = false
        } else if status == .working {
            statusText = "🤖 Robot working"
            statusAnimated = true
            working = true
        } else if status == .done {
            statusText = "👤 Done. Presenting your results"
            statusAnimated = false
            working = false
            done = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onResult(.success)
            }
        } else if status == .failure {
            statusText = "❌  Could not complete operation"
            statusAnimated = false
            working = false
            done = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onResult(.failure)
            }
        }
    }
}

enum Status {
    case login
    case working
    case done
    case failure
}

struct WebViewWrapper: UIViewControllerRepresentable {
    var onClose: () -> Void
    var onStatusChange: (_ status: Status) -> Void
    var initialized: Bool = false

    init(onClose: @escaping () -> Void, onStatusChange: @escaping (_ status: Status) -> Void) {
        self.onClose = onClose
        self.onStatusChange = onStatusChange
    }

    // This function makes the WKWebView
    func makeUIViewController(context _: UIViewControllerRepresentableContext<WebViewWrapper>) -> WKWebViewController {
        let uiViewController = WKWebViewController()
        uiViewController.onClose = onClose
        uiViewController.onStatusChange = onStatusChange

        return uiViewController
    }

    // This function is called when the WKWebView is created to load the request
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
    var webView: WKWebView!
    var isStarted: Bool = false
    var onClose: (() -> Void)!
    var onStatusChange: ((_ status: Status) -> Void)!

    override func loadView() {
        view = UIView()

//        deleteAllCookies()

        // set user agent to get around google oauth issues
        let webViewConfiguration = WKWebViewConfiguration()

        // to get around google oauth
        webViewConfiguration.applicationNameForUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3.1 Mobile/15E148 Safari/604.1"

        // Set up resizing rules.
        webView = WKWebView(frame: .zero)

        let closeButtonItem = BlockBarButtonItem(title: "Close", style: .plain, actionHandler: {
            self.webView.stopLoading()
            self.webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            self.onClose()
        })

        let logoutButtonItem = BlockBarButtonItem(title: "Log out", style: .plain, actionHandler: {
            deleteAllCookies()
            self.onClose()
        })

        // Create a toolbar
        let toolbar = UIToolbar()
        toolbar.items = [closeButtonItem, logoutButtonItem]
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        view.addSubview(toolbar)
        webView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolbar.leftAnchor.constraint(equalTo: view.leftAnchor),
            toolbar.rightAnchor.constraint(equalTo: view.rightAnchor),

            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
        ])
    }

    // Handles orchestrating between the Agent, the PipeablePage, and the AirBnBTools
    func start() async throws {
        // No re-entry.
        isStarted = true

        let page = PipeablePage(webView, debugPrintConsoleLogs: true)

        do {
            let airBnbTools = AirBnBTools(page: page)

            onStatusChange(.login)
            try await airBnbTools.login()

            onStatusChange(.working)

            let agent = Agent(airBnBTools: airBnbTools, openAIAPIToken: "YOUR_OPENAI_API_KEY")
            let msg = "Book a place in Seoul for 2 adults on March 20th to March 22nd, 2024 and enable instant book for a place that costs between $100 and $150 per night, and book the entire place."

            var res = try await agent.step(message: msg)
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

struct Cookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
}

public func getCookiesJSON(webView: WKWebView) async throws -> String {
    return try await withCheckedThrowingContinuation { continuation in
        Task {
            await MainActor.run {
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    let cookieObjects = cookies.map { Cookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path) }
                    do {
                        let jsonData = try JSONEncoder().encode(cookieObjects)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            continuation.resume(returning: jsonString)
                        } else {
                            continuation.resume(throwing: NSError(domain: "Invalid JSON data", code: -1, userInfo: nil))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

public func getUserAgent(webView: WKWebView) async throws -> String {
    return try await withCheckedThrowingContinuation { continuation in
        Task {
            await MainActor.run {
                webView.evaluateJavaScript("navigator.userAgent") { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let userAgent = result as? String {
                        continuation.resume(returning: userAgent)
                    } else {
                        continuation.resume(returning: "")
                    }
                }
            }
        }
    }
}

class BlockBarButtonItem: UIBarButtonItem {
    private var actionHandler: (() -> Void)?

    convenience init(title: String?, style: UIBarButtonItem.Style, actionHandler: (() -> Void)?) {
        self.init(title: title, style: style, target: nil, action: #selector(barButtonItemPressed))
        target = self
        self.actionHandler = actionHandler
    }

    convenience init(image: UIImage?, style: UIBarButtonItem.Style, actionHandler: (() -> Void)?) {
        self.init(image: image, style: style, target: nil, action: #selector(barButtonItemPressed))
        target = self
        self.actionHandler = actionHandler
    }

    @objc func barButtonItemPressed(sender _: UIBarButtonItem) {
        actionHandler?()
    }
}

func randomString(length: Int) -> String {
    let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0 ..< length).map { _ in characters.randomElement()! })
}
