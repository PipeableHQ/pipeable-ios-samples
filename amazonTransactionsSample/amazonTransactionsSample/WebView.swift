import Foundation
import PipeableSDK
import SwiftUI
import WebKit

enum ResultStatus {
    case success
    case failure
}

struct PipeableWebView: View {
    @Binding var orders: [AmazonOrder]
    var onClose: () -> Void
    var onResult: (ResultStatus) -> Void

    @State var working = false
    @State var done = false

    var body: some View {
        ZStack {
            WebViewWrapper(orders: $orders, onClose: onClose, onStatusChange: onStatusChange)
                .blur(radius: working ? 2.5 : 0)
                .allowsHitTesting(!working)
        }
    }

    func onStatusChange(_ status: Status, _ newOrders: [AmazonOrder]) {
        orders = newOrders

        if status == .login {
            working = false
        } else if status == .working {
            working = true
        } else if status == .done {
            working = false
            done = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onResult(.success)
            }
        } else if status == .failure {
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
    @Binding var orders: [AmazonOrder]

    var onClose: () -> Void
    var onStatusChange: (_ status: Status, _ orders: [AmazonOrder]) -> Void

    // This function makes the WKWebView
    func makeUIViewController(context: UIViewControllerRepresentableContext<WebViewWrapper>) -> WKWebViewController {
        let uiViewController = WKWebViewController(onClose: onClose, onStatusChange: onStatusChange)
        uiViewController.orders = orders
        return uiViewController
    }

    // This function is called when the WKWebView is created to load the request, we use it to kick off the
    // async work of running the automation.
    func updateUIViewController(_ uiViewController: WKWebViewController, context: UIViewControllerRepresentableContext<WebViewWrapper>) {
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
    var webView: WKWebView
    var isStarted = false
    var onClose: () -> Void
    var onStatusChange: (_ status: Status, _ orders: [AmazonOrder]) -> Void
    var orders: [AmazonOrder] = []

    init(onClose: @escaping () -> Void, onStatusChange: @escaping (_ status: Status, _ orders: [AmazonOrder]) -> Void) {
        self.webView = WKWebView()
        self.onClose = onClose
        self.onStatusChange = onStatusChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView()

        // Set up resizing rules.
        webView = WKWebView(frame: .zero)

        // Only for iOS versions above 16.4
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        let closeButtonItem = BlockBarButtonItem(title: "Close", style: .plain) {
            self.webView.stopLoading()
            self.webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            self.onClose()
        }

        // Create a toolbar
        let toolbar = UIToolbar()
        toolbar.items = [closeButtonItem]
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        view.addSubview(toolbar)
        webView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolbar.leftAnchor.constraint(equalTo: view.leftAnchor),
            toolbar.rightAnchor.constraint(equalTo: view.rightAnchor),
        ])
    }

    func start() async throws {
        // No re-entry.
        isStarted = true
        
        // The webview will automatically cache cookies, so we delete all
        // cookies each time to make the experience repeatable.
        deleteAllCookies()

        // Initialize the PipeablePage, the resulting instance will be used to
        // drive interactions with a webpage and read back contents.
        let page = PipeablePage(webView)

        // Navigate to the Amazon home page, click the login button, then wait for the user to log in
        onStatusChange(.login, [])
        
        _ = try await page.goto("https://www.amazon.com")
        
        let loginLink = try await page.waitForSelector("a#nav-logobar-greeting")
        try await loginLink?.click()
        
        // Wait for the user to log in, once the user has successfully logged in
        // they will be redirected to the final url below, this is how we know they
        // finished the login process and we can proceed.
        try await page.waitForURL { url in
            url == "https://www.amazon.com/?_encoding=UTF8&ref_=navm_hdr_signin"
        }

        do {
            // Now that the user is logged in we can fetch their Amazon transactions
            // directly from the DOM. We first navigate to the correct url and only
            // select the transactions for a specific year.
            onStatusChange(.working, [])
            
            
            let year = 2024
            _ = try await page.goto(
                "https://www.amazon.com/gp/css/order-history/ref=ppx_yo2ov_mob_b_filter_y\(year)_all?ie=UTF8&digitalOrders=0&orderFilter=year-\(year)&search=&startIndex=0&unifiedOrders=0"
            )
            
            try await page.waitForURL { url in
                url.contains("orderFilter=year-\(year)")
            }
            
            // Fetch the user's Amazon transactions using the PipeableSDK
            // directly.
            try await fetchTransactionsUsingPipeableNative(page: page)
            
            // Fetch the user's Amazon transactions using PipeableScript,
            // to try this out comment out the call to fetchTransactionsUsingPipeableNative
            // above and uncomment the next line.
            // try await fetchTransactionsUsingPipebleScript(page: page)
            
            onStatusChange(.done, orders)
        } catch {
            print("Got error: \(error)")
            onStatusChange(.failure, orders)
            return
        }
    }
    
    func fetchTransactionsUsingPipeableNative(page: PipeablePage) async throws {
        // This function fetches the user's Amazon transactions using the PipeableSDK directly (i.e using the Swift API).
        let orderEls = try await page.querySelectorAll("#ordersContainer .js-item")
        
        for orderEl in orderEls {
            let orderImage = try await orderEl.querySelector("img")
            let imageAlt = try await orderImage?.getAttribute("alt")
            
            let orderDateEl = try await orderEl.querySelector(".a-size-small")
            
            let orderDateRawText = try await orderDateEl?.textContent()
            let orderDate = orderDateRawText?
                .replacingOccurrences(
                    of: "Ordered on",
                    with: "",
                    options: .caseInsensitive
                )
                .replacingOccurrences(
                    of: "Delivered",
                    with: "",
                    options: .caseInsensitive
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let anOrder = AmazonOrder(item: imageAlt ?? "", date: orderDate ?? "")
            orders.append(anOrder)
        }
    }
    
    func fetchTransactionsUsingPipebleScript(page: PipeablePage) async throws {
        // This function fetches the user's Amazon transactions using a PipeableScript instead.
        // Run the PipeableScript
        let result = try await runScript(
            """
                const orderEls = await page.querySelectorAll("#ordersContainer .js-item");
            
                const result = [];
            
                for (const orderEl of orderEls) {
                    const orderImage = await orderEl.querySelector("img");
                    const imageAlt = await orderImage.getAttribute("alt");
            
                    const orderDateEl = await orderEl.querySelector(".a-size-small")
            
                    const orderDateRawText = await orderDateEl.textContent();
                    const orderDate = orderDateRawText.replace(/Ordered on/i, "").replace(/Delivered/i, "").trim();
            
                    const anOrder = {
                        item: imageAlt,
                        orderDate: orderDate
                    };
                    result.push(anOrder);
                }
            
                return result;
            """, page
        )
        
        // Convert the results to Swift objects
        if let array = result.toObject() as? [Any] {
            // Iterate over each element in the array, which are now expected to be dictionaries
            for element in array {
                if let dictionary = element as? [String: Any] {
                    // Extract 'item' and 'field' values from the dictionary
                    let item = dictionary["item"] as? String
                    let orderDate = dictionary["orderDate"] as? String
                    
                    let anOrder = AmazonOrder(item: item ?? "", date: orderDate ?? "")
                    orders.append(anOrder)
                }
            }
        }
    }
}

public func deleteAllCookies() {
    let dataStore = WKWebsiteDataStore.default()
    let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
    let dateFrom = Date(timeIntervalSince1970: 0)

    dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom) {}
}

class BlockBarButtonItem: UIBarButtonItem {
    private var actionHandler: (() -> Void)?

    convenience init(title: String?, style: UIBarButtonItem.Style, actionHandler: (() -> Void)?) {
        self.init(title: title, style: style, target: nil, action: #selector(barButtonItemPressed))
        self.target = self
        self.actionHandler = actionHandler
    }

    convenience init(image: UIImage?, style: UIBarButtonItem.Style, actionHandler: (() -> Void)?) {
        self.init(image: image, style: style, target: nil, action: #selector(barButtonItemPressed))
        self.target = self
        self.actionHandler = actionHandler
    }

    @objc func barButtonItemPressed(sender: UIBarButtonItem) {
        actionHandler?()
    }
}