import Foundation
import PipeableSDK
import SwiftUI
import WebKit


struct PipeableWebViewWrapper: UIViewRepresentable {
    @Binding var orders: [AmazonOrder]
    var onClose: () -> Void

    func makeUIView(context _: Context) -> PipeableWebView {
        // The webview will automatically cache cookies, so we delete all
        // cookies each time to make the experience repeatable.
        deleteAllCookies()

        // Initialize the PipeablePage, the resulting instance will be used to
        // drive interactions with a webpage and read back contents.
        let webView = PipeableWebView()
        let page = webView.page

        Task {
            
            // Navigate to the Amazon home page, click the login button, then wait for the user to log in
            _ = try await page.goto("https://www.amazon.com")
            
            let loginLink = try await page.waitForSelector("a#nav-logobar-greeting")
            try await loginLink?.click()
            
            // Wait for the user to log in, once the user has successfully logged in
            // they will be redirected to the final url below, this is how we know they
            // finished the login process and we can proceed.
            try await page.waitForURL { url in
                url == "https://www.amazon.com/?_encoding=UTF8&ref_=navm_hdr_signin"
            }

            // Now that the user is logged in we can fetch their Amazon transactions
            // directly from the DOM. We first navigate to the correct url and only
            // select the transactions for a specific year.
            
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
            
            onClose()
        }

        return webView
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

    func updateUIView(_: PipeableWebView, context _: Context) {
        // Since our demo app is very simple, everything happens during creation
        // and no ui view updates are triggered.
    }
}

struct PipeableWebview_Previews: PreviewProvider {
    @State private static var orders: [AmazonOrder] = []

    static var previews: some View {
        VStack {
            PipeableWebViewWrapper(orders: $orders) {}
        }
    }
}

public func deleteAllCookies() {
    let dataStore = WKWebsiteDataStore.default()
    let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
    let dateFrom = Date(timeIntervalSince1970: 0)

    dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom) {}
}
