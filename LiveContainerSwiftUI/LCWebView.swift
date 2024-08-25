//
//  SwiftUIView.swift
//  nmsl
//
//  Created by s s on 2024/8/23.
//

import SwiftUI
import WebKit

struct LCWebView: View {
    @State private var webView : WebView
    @State private var didAppear = false
    
    @Binding var url : URL
    @Binding var isPresent: Bool
    @State private var loadStatus = 0.0
    @State private var uiLoadStatus = 0.0
    @State private var pageTitle = ""
    
    @Binding var apps : [LCAppInfo]
    
    @State private var runAppAlertShow = false
    @State private var runAppAlertMsg = ""
    @State private var doRunApp = false
    @State private var renameFolderContent = ""
    @State private var doRunAppSemaphore = DispatchSemaphore(value: 0)
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    init(url: Binding<URL>, apps: Binding<[LCAppInfo]>, isPresent: Binding<Bool>) {
        self.webView = WebView()
        self._url = url
        self._apps = apps
        self._isPresent = isPresent
    }
    
    var body: some View {
        
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Button(action: {
                        webView.goBack()
                    }, label: {
                        Image(systemName: "chevron.backward")
                    })
                    
                    Button(action: {
                        webView.goForward()
                    }, label: {
                        Image(systemName: "chevron.forward")
                    }).padding(.horizontal)
                }
                
                Spacer()
                Text(pageTitle)
                    .lineLimit(1)
                Spacer()
                Button(action: {
                    webView.reload()
                }, label: {
                    Image(systemName: "arrow.clockwise")
                }).padding(.horizontal)
                Button(action: {
                    isPresent = false
                }, label: {
                    Text("Done")
                })
                
            }
            .padding([.bottom, .horizontal])
            .background(Color(.systemGray6))
            .overlay(alignment: .bottomTrailing) {
                ProgressView(value: uiLoadStatus)
                    .opacity(loadStatus == 1.0 ? 0 : 1)
                    .scaleEffect(y: 0.5)
                    .offset(y: 1)
                    .onChange(of: loadStatus) { newValue in
                        if newValue > uiLoadStatus {
                            withAnimation(.easeIn(duration: 0.3)) {
                                uiLoadStatus = newValue
                            }
                        } else {
                            uiLoadStatus = newValue
                        }
                    }
                
            }
            webView
        }
        .onAppear(){
            webView.loadURL(url: url)
            if !didAppear {
                onViewAppear()
                didAppear = true
            }

        }
        .alert("Run App", isPresented: $runAppAlertShow) {
            Button("Run", action: {
                self.doRunApp = true
                self.doRunAppSemaphore.signal()
            })
            Button("Cancel", role: .cancel, action: {
                self.doRunApp = false
                self.doRunAppSemaphore.signal()
            })
        } message: {
            Text(runAppAlertMsg)
        }
        .alert("Error", isPresented: $errorShow) {
            Button("OK", action: {
            })
        } message: {
            Text(errorInfo)
        }
        
    }
    
    func onViewAppear() {
        let observer = WebViewLoadObserver(loadStatus: $loadStatus, webView: self.webView.webView)
        let webViewDelegate = WebViewDelegate(pageTitle: $pageTitle, urlSchemeHandler:onURLSchemeDetected)
        webView.setDelegate(delegete: webViewDelegate)
        webView.setObserver(observer: observer)
    }
    
    public func onURLSchemeDetected(url: URL) {
        DispatchQueue.global().async {
            var appToLaunch : LCAppInfo? = nil
        appLoop: for app in apps {
                if let schemes = app.urlSchemes() {
                    for scheme in schemes {
                        if let scheme = scheme as? String, scheme == url.scheme {
                            appToLaunch = app
                            break appLoop
                        }
                    }
                }
            }
            
            guard let appToLaunch = appToLaunch else {
                errorInfo = "Scheme \"\(url.scheme!)\" cannot be opened by any app installed in LiveContainer."
                errorShow = true
                return
            }
            
            runAppAlertMsg = "This web page is trying to launch \"\(appToLaunch.displayName()!)\", continue?"
            runAppAlertShow = true
            self.doRunAppSemaphore.wait()
            if !doRunApp {
                return
            }
            
            UserDefaults.standard.setValue(appToLaunch.relativeBundlePath!, forKey: "selected")
            UserDefaults.standard.setValue(url.absoluteString, forKey: "launchAppUrlScheme")
            LCUtils.launchToGuestApp()
        }
    }
}

class WebViewLoadObserver : NSObject {
    private var loadStatus: Binding<Double>
    private var webView: WKWebView
    
    init(loadStatus: Binding<Double>, webView: WKWebView) {
        self.loadStatus = loadStatus
        self.webView = webView
        super.init()
        self.webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil);
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            loadStatus.wrappedValue = self.webView.estimatedProgress
        }
    }
    

}

class WebViewDelegate : NSObject,WKNavigationDelegate {
    private var pageTitle: Binding<String>
    private var urlSchemeHandler: (URL) -> Void
    
    init(pageTitle: Binding<String>, urlSchemeHandler: @escaping (URL) -> Void) {
        self.pageTitle = pageTitle
        self.urlSchemeHandler = urlSchemeHandler
        super.init()
    }
    
    func webView(_ webView: WKWebView,
                   decidePolicyFor navigationAction: WKNavigationAction,
                   decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler((WKNavigationActionPolicy)(rawValue: WKNavigationActionPolicy.allow.rawValue + 2)!)
        guard let scheme = navigationAction.request.url?.scheme else {
            return
        }
        if(scheme == "https" || scheme == "http" || scheme == "about" || scheme == "itms-appss") {
            return;
        }
        urlSchemeHandler(navigationAction.request.url!)

    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.pageTitle.wrappedValue = webView.title!
    }
    
    
}

struct WebView: UIViewRepresentable {
    
    let webView: WKWebView
    var observer: WebViewLoadObserver?
    var delegate: WKNavigationDelegate?
    
    init() {
        self.webView = WKWebView()
    }
    
    mutating func setDelegate(delegete: WKNavigationDelegate) {
        self.delegate = delegete
        self.webView.navigationDelegate = delegete
    }
    
    mutating func setObserver(observer: WebViewLoadObserver) {
        self.observer = observer
    }
    
    func makeUIView(context: Context) -> WKWebView {
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        
    }
    
    func reload() {
        webView.reload()
    }
    
    func goBack(){
        webView.goBack()
    }
    
    func goForward(){
        webView.goForward()
    }
    
    
    func loadURL(url: URL) {
        webView.load(URLRequest(url: url))
    }
    

}

