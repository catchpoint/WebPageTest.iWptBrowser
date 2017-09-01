//
//  ViewController.swift
//  iWptBrowser
//
//  Created by Patrick Meenan on 8/30/17.
//  Copyright © 2017 WebPageTest LLC. All rights reserved.
//
import WebKit
import UIKit

extension String {
  func base64Encoded() -> String? {
    if let data = self.data(using: .utf8) {
      return data.base64EncodedString()
    }
    return nil
  }
  
  func base64Decoded() -> String? {
    if let data = Data(base64Encoded: self) {
      return String(data: data, encoding: .utf8)
    }
    return nil
  }
}

class ViewController: UIViewController, WKNavigationDelegate {
  var webView: WKWebView?
  var clientSocket:Socket?
  var buffer_in = ""
  var hasOrange = false
  let startPage = "<html>\n" +
                  "<head>\n" +
                  "<style>\n" +
                  "body {background-color: white; margin: 0;}\n" +
                  "</style>\n" +
                  "</head>\n" +
                  "<body><div id='wptorange' style='position: absolute; top: 0; left: 0; right: 0; bottom: 0; background-color: #DE640D'></div></body>\n" +
                  "</html>"
  let showOrange =  "(function() {" +
                    "var wptDiv = document.createElement('div');" +
                    "wptDiv.id = 'wptorange';" +
                    "wptDiv.style.position = 'absolute';" +
                    "wptDiv.style.top = '0';" +
                    "wptDiv.style.left = '0';" +
                    "wptDiv.style.right = '0';" +
                    "wptDiv.style.bottom = '0';" +
                    "wptDiv.style.zIndex = '2147483647';" +
                    "wptDiv.style.backgroundColor = '#DE640D';" +
                    "document.body.appendChild(wptDiv);" +
                    "})();"
  let hideOrange =  "(function() {" +
                    "var wptDiv = document.getElementById('wptorange');" +
                    "wptDiv.parentNode.removeChild(wptDiv);" +
                    "})();"
  
  func log(_ message: String) {
    NSLog("iWptBrowser: \(message)")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.view.backgroundColor = UIColor.black
    title = "iWptBrowser"
    self.edgesForExtendedLayout = []
    let queue = DispatchQueue(label: "org.webpagetest.socketlisten", attributes: .concurrent)
    queue.async {
      self.socketListenThread()
    }
  }
  
  func handleMessage(_ message:String) {
    self.log("<< \(message.replacingOccurrences(of: "\t", with: " "))")
    let parts = message.components(separatedBy: "\t")
    if parts.count >= 1 {
      var id = ""
      var message = ""
      let idParts = parts[0].components(separatedBy: ":")
      if idParts.count > 1 {
        id = idParts[0]
        message = idParts[1].lowercased()
      } else {
        message = idParts[0].lowercased()
      }
      var data:String?
      if parts.count > 1 {
        data = parts[1]
      }
      let messageParts = message.components(separatedBy: ".")
      if messageParts.count > 1 {
        message = messageParts[0]
        for i in 1..<messageParts.count {
          switch messageParts[i] {
            case "encoded":
              if data != nil {
                data = data!.base64Decoded()
              }
            default:
              self.log("Unknown command option: \(messageParts[i])")
          }
        }
      }
      switch message {
        case "clearcache": clearCache(id:id)
        case "startbrowser": startBrowser(id:id)
        case "closebrowser", "stopbrowser": closeBrowser(id:id)
        case "navigate":
          if data != nil {
            navigate(id:id, to:data!)
          } else {
            sendMessage(id:id, message:"ERROR", data:"Missing URL for navigation")
          }
        case "addorange", "setorange": addOrange(id:id)
        case "exec":
          if data != nil {
            execScript(id:id, script:data!)
          } else {
            sendMessage(id:id, message:"ERROR", data:"Missing script for exec")
          }
        default:
          sendMessage(id:id, message:"ERROR", data:"Unknown command: \(message)")
      }
    }
  }
  
  /*************************************************************************************
                                  browser operations
   *************************************************************************************/
  func clearCache(id:String) {
    sendMessage(id:id, message:"OK")
  }
  
  func startBrowser(id:String) {
    if webView != nil {
      webView!.navigationDelegate = nil
      webView!.removeFromSuperview()
      webView = nil
    }
    webView = WKWebView()
    webView!.frame = self.view.bounds
    self.view.addSubview(webView!)
    webView!.loadHTMLString(startPage, baseURL: URL(string: "http://www.webpagetest.org"))
    hasOrange = true
    webView!.navigationDelegate = self
    title = ""
    sendMessage(id:id, message:"OK")
  }
  
  func closeBrowser(id:String) {
    if webView != nil {
      webView!.navigationDelegate = nil
      webView!.removeFromSuperview()
      webView = nil
    }
    hasOrange = false
    title = "iWptBrowser"
    sendMessage(id:id, message:"OK")
  }
  
  func navigate(id:String, to:String) {
    if webView != nil {
      var url = to
      if !url.hasPrefix("http") {
        url = "http://" + url
      }
      title = "Loading..."
      webView!.load(URLRequest(url: URL(string:url)!))
      sendMessage(id:id, message:"OK")
    } else {
      sendMessage(id:id, message:"ERROR", data:"Browser not started")
    }
  }
  
  func addOrange(id:String) {
    if webView != nil {
      webView!.evaluateJavaScript(showOrange) { (result, error) in
        self.sendMessage(id:id, message:"OK")
      }
    } else {
      sendMessage(id:id, message:"ERROR", data:"Browser not started")
    }
  }
  
  func execScript(id:String, script:String) {
    if webView != nil {
      webView!.evaluateJavaScript(script) { (result, error) in
        var ok = "OK"
        var returned = ""
        if error != nil {
          ok = "ERROR"
          returned = "\(error!)"
        }
        if result != nil {
          returned = "\(result!)"
        }
        if returned.range(of: "\t") != nil {
          ok += ".encoded"
          returned = returned.base64Encoded()!
        }
        self.sendMessage(id:id, message:ok, data:returned)
      }
    } else {
      sendMessage(id:id, message:"ERROR", data:"Browser not started")
    }
  }
  
  /*************************************************************************************
                                  Webview interfaces
   *************************************************************************************/
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    title = webView.title
    self.sendNotification(message: "page.didFinish")
  }
  
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let url = navigationAction.request.url!
    if navigationAction.targetFrame == nil || navigationAction.targetFrame!.isMainFrame {
      self.sendNotification(message: "page.navigateStart", data:url.absoluteString)
      if hasOrange {
        webView.evaluateJavaScript(hideOrange) { (result, error) in
          decisionHandler(.allow)
        }
      } else {
        decisionHandler(.allow)
      }
    } else {
      self.sendNotification(message: "page.navigateFrameStart", data:url.absoluteString)
      decisionHandler(.allow)
    }
  }
  
  /*************************************************************************************
                                Agent socket interface
   *************************************************************************************/
  func sendNotification(message:String) {
    sendMessage(id:"", message:message, data:"")
  }
  
  func sendNotification(message:String, data:String) {
    sendMessage(id:"", message:message, data:data)
  }
  
  func sendMessage(id:String, message:String) {
    sendMessage(id:id, message:message, data:"")
  }

  func sendMessage(id:String, message:String, data:String) {
    let queue = DispatchQueue(label: "org.webpagetest.message", attributes: .concurrent)
    queue.async {
      var str = id
      if str.characters.count > 0 {
        str += ":"
      }
      str += message
      if data.characters.count > 0 {
        str += "\t"
        str += data
      }
      str += "\n"
      self.sendMessageAsync(str)
    }
  }
  
  func sendMessageAsync(_ message:String) {
    if clientSocket != nil {
      self.log(">> \(message)")
      do {
        try clientSocket!.write(from:message)
      } catch let err {
        self.log("Socket write error: \(err)")
      }
    }
  }
  
  func socketListenThread() {
    self.log("Running socket thread")
    do {
      let socket = try Socket.create()
      socket.readBufferSize = 65535
      try socket.listen(on: 19222)
      var count = 0
      repeat {
        let client = try socket.acceptClientConnection()
        if clientSocket != nil {
          clientSocket!.close()
        }
        clientSocket = client
        count += 1
        self.log("Agent #\(count) connected")
        let queue = DispatchQueue(label: "org.webpagetest.socket\(count)", attributes: .concurrent)
        queue.async {
          self.pumpSocket(client, count)
        }
      } while true
    } catch let err {
      self.log("Socket exception: \(err)")
    }
  }
  
  func pumpSocket(_ socket:Socket, _ id:Int) {
    var cont = true
    do {
      try socket.setReadTimeout(value: 10000)
    } catch let err {
      self.log("\(id): Socket Read timeout error: \(err)")
    }
    repeat {
      do {
        let str = try socket.readString()
        if (str != nil) {
          self.receivedRawData(id:id, str:str!)
        }
      } catch let err {
        self.log("\(id): Socket Read error: \(err)")
        cont = socket.isConnected
      }
    } while cont
    socket.close()
    self.log("\(id): Socket closed")
  }
  
  func receivedRawData(id:Int, str:String) {
    for ch in str.characters {
      if ch == "\n" || ch == "\r" || ch == "\r\n" {
        if buffer_in.characters.count > 0 {
          let message = self.buffer_in
          self.buffer_in = ""
          DispatchQueue.main.async {
            self.handleMessage(message)
          }
        }
      } else {
        buffer_in.append(ch)
      }
    }
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
  }


}

