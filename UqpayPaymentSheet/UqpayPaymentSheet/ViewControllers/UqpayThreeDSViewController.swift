import UIKit
import WebKit

/// Presents the issuer's 3D Secure step inside the app.
///
/// Two shapes arrive from `next_action`:
///
/// - `redirect_iframe` carries an HTML fragment containing a `method="POST"`
///   form aimed at the issuer's access control server. It must be loaded as
///   HTML and allowed to submit itself. Rewriting it as a `GET` navigation
///   drops the form body and authentication fails.
/// - `redirect_to_url` carries a URL to load directly, used for the challenge
///   screen where the customer enters an OTP.
///
/// This controller only displays the step. It never decides the outcome —
/// the caller confirms that by re-reading the payment intent, because the
/// authoritative result is delivered to your backend by webhook and a device
/// can lose connectivity or be tampered with at any point.
final class UqpayThreeDSViewController: UIViewController {

    enum Content {
        /// HTML fragment from `next_action.redirect_iframe.iframe`.
        case iframeHTML(String)
        /// URL from `next_action.redirect_to_url.url`.
        case url(URL)
    }

    /// Called when the customer dismisses the screen without finishing.
    var onCancel: (() -> Void)?

    /// Called when the web view reaches the merchant's return URL.
    ///
    /// This signals only that the browser step ended — not that the payment
    /// succeeded. Verify the intent status before telling the customer anything.
    var onReachedReturnURL: (() -> Void)?

    private let content: Content
    private let returnURLPrefixes: [String]
    private let appearance: PaymentSheet.Appearance

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }()

    private lazy var progressView: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    /// - Parameter returnURLPrefixes: URLs that mark the end of the browser
    ///   step: the merchant's configured return scheme and/or the `return_url`
    ///   the API echoed back in `next_action.redirect_to_url`. Empty entries
    ///   are ignored.
    init(
        content: Content,
        returnURLPrefixes: [String?],
        appearance: PaymentSheet.Appearance
    ) {
        self.content = content
        self.returnURLPrefixes = returnURLPrefixes.compactMap { $0 }.filter { !$0.isEmpty }
        self.appearance = appearance
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Presented modally, so the nav controller's style is not inherited:
        // apply the merchant's choice directly.
        overrideUserInterfaceStyle = appearance.userInterfaceStyle
        view.backgroundColor = appearance.backgroundColor
        title = "Authentication"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        view.addSubview(webView)
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            progressView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        progressView.startAnimating()
        load()
    }

    private func load() {
        switch content {
        case .url(let url):
            webView.load(URLRequest(url: url))

        case .iframeHTML(let fragment):
            // A real https base URL is required. Loading against about:blank
            // gives the document an opaque origin, and some access control
            // servers refuse the submission that follows.
            let base = URL(string: "https://uqpaytech.com")
            webView.loadHTMLString(Self.document(wrapping: fragment), baseURL: base)
        }
    }

    /// Wraps the fragment in a document and submits the form.
    ///
    /// The fragment usually carries its own auto-submit script. Submitting
    /// again is harmless when it does, and is what makes the step work when
    /// it does not.
    private static func document(wrapping fragment: String) -> String {
        """
        <!doctype html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="margin:0;background:transparent">
        \(fragment)
        <script>
        (function () {
          var submit = function () {
            var forms = document.getElementsByTagName('form');
            if (forms.length > 0) { forms[0].submit(); }
          };
          if (document.readyState === 'complete') { submit(); }
          else { window.addEventListener('load', submit); }
        })();
        </script>
        </body>
        </html>
        """
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    /// True when the URL is the merchant's return URL rather than part of the
    /// issuer's flow.
    private func isReturnURL(_ url: URL) -> Bool {
        let urlString = url.absoluteString
        return returnURLPrefixes.contains { urlString.hasPrefix($0) }
    }
}

extension UqpayThreeDSViewController: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // A custom scheme cannot be loaded by the web view. Intercept it and
        // treat it as the end of the browser step.
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" {
            decisionHandler(.cancel)
            onReachedReturnURL?()
            return
        }

        if isReturnURL(url) {
            decisionHandler(.cancel)
            onReachedReturnURL?()
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progressView.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        progressView.stopAnimating()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        progressView.stopAnimating()
    }
}
