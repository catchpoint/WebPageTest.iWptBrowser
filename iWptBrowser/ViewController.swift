//
//  ViewController.swift
//  iWptBrowser
//
//  Created by Patrick Meenan on 8/30/17.
//  Copyright © 2017 WebPageTest LLC. All rights reserved.
//
import WebKit
import UIKit

class ViewController: UIViewController, WKNavigationDelegate {
  var webView: WKWebView?
  var clientSocket:Socket?
  var buffer_in = ""
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
    self.edgesForExtendedLayout = []
    let queue = DispatchQueue(label: "org.webpagetest.socketlisten", attributes: .concurrent)
    queue.async {
      self.socketListenThread()
    }
  }
  
  func handleMessage(_ message:String) {
    self.log("<< \(message)")
    let parts = message.components(separatedBy: " ")
    if parts.count >= 2 {
      let id = parts[0]
      let message = parts[1].lowercased()
      var response = "OK"
      switch message {
        case "clearcache":
          clearCache()
        case "startbrowser":
          startBrowser()
        case "closebrowser":
          closeBrowser()
        case "navigate":
          if parts.count >= 3 {
            let url = parts[2]
            navigate(url)
          } else {
            response = "ERROR"
          }
        default:
          response = "ERROR"
      }
      sendMessage(id:id, message:response)
    }
  }
  
  /*************************************************************************************
                                  browser operations
   *************************************************************************************/
  func clearCache() {
  }
  
  func startBrowser() {
    if webView != nil {
      self.closeBrowser()
    }
    webView = WKWebView()
    webView!.frame = self.view.bounds
    self.view.addSubview(webView!)
    webView!.loadHTMLString(startPage, baseURL: URL(string: "http://www.webpagetest.org"))
    webView!.navigationDelegate = self
  }
  
  func closeBrowser() {
    if webView != nil {
      webView!.navigationDelegate = nil
      webView!.removeFromSuperview()
      webView = nil
    }
  }
  
  func navigate(_ to:String) {
    if webView != nil {
      var url = to
      if !url.hasPrefix("http") {
        url = "http://" + url
      }
      webView!.load(URLRequest(url: URL(string:url)!))
    }
  }
  
  /*************************************************************************************
                                  Webview interfaces
   *************************************************************************************/
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    title = webView.title
    self.sendNotification(message: "navigate:end")
  }
  
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let url = navigationAction.request.url!
    self.sendNotification(message: "navigate:start", data:url.absoluteString)
    webView.evaluateJavaScript(hideOrange) { (result, error) in
      decisionHandler(.allow)
    }
  }
  
  /*************************************************************************************
                                Agent socket interface
   *************************************************************************************/
  func sendNotification(message:String) {
    sendMessage(id:"0", message:message, data:"")
  }
  
  func sendNotification(message:String, data:String) {
    sendMessage(id:"0", message:message, data:data)
  }
  
  func sendMessage(id:String, message:String) {
    sendMessage(id:id, message:message, data:"")
  }

  func sendMessage(id:String, message:String, data:String) {
    let queue = DispatchQueue(label: "org.webpagetest.message", attributes: .concurrent)
    queue.async {
      self.sendMessageAsync("\(id) \(message) \(data)")
    }
  }
  
  func sendMessageAsync(_ message:String) {
    if clientSocket != nil {
      self.log(">> \(message)")
      do {
        //try clientSocket!.write(from:message)
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
        cont = false
      }
    } while cont
    socket.close()
    self.log("\(id): Socket closed")
  }
  
  func receivedRawData(id:Int, str:String) {
    for (_, ch) in str.characters.enumerated() {
      if ch == "\n" {
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

