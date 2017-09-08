//
//  ViewController.swift
//  iWptBrowser
//
//  Created by Patrick Meenan on 8/30/17.
//  Copyright © 2017 WebPageTest LLC. All rights reserved.
//
import Darwin
import UIKit
import WebKit

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

extension UINavigationController {
  override open var shouldAutorotate: Bool {
    return true
  }
  
  override open var supportedInterfaceOrientations: UIInterfaceOrientationMask{
    get {
      if let visibleVC = visibleViewController {
        return visibleVC.supportedInterfaceOrientations
      }
      return super.supportedInterfaceOrientations
    }
  }}

class ViewController: UIViewController, WKNavigationDelegate {
  var startTime = DispatchTime.now()
  var webView: WKWebView?
  var clientSocket:Socket?
  var videoCapture:ASScreenRecorder?
  var videoUrl: URL?
  var buffer_in = ""
  var hasOrange = false
  var isLandscape = false
  var isActive = false
  let startPage = "<html>\n" +
                  "<head>\n" +
                  "<style>\n" +
                  "body {background-color: white; margin: 0;}\n" +
                  "</style>\n" +
                  "</head>\n" +
                  "<body></body>\n" +
                  "</html>"
  
  func log(_ message: String) {
    //NSLog("iWptBrowser (\(self.timestamp())): \(message.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: ""))")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    UIApplication.shared.isIdleTimerDisabled = true
    UIScreen.main.brightness = 0.0
    videoUrl = URL(fileURLWithPath: NSHomeDirectory())
    videoUrl!.appendPathComponent("tmp/video.mp4")
    self.log("Video URL: \(videoUrl!)")
    deleteVideo()
    self.view.backgroundColor = UIColor.black
    title = "iWptBrowser"
    self.edgesForExtendedLayout = []
    let queue = DispatchQueue(label: "org.webpagetest.socketlisten", attributes: .concurrent)
    queue.async {
      self.socketListenThread()
    }
  }
  
  override func didReceiveMemoryWarning() {
    self.log("didReceiveMemoryWarning")
    super.didReceiveMemoryWarning()
  }

  func timestamp() -> Double {
    let now = DispatchTime.now()
    let nanoTime = now.uptimeNanoseconds - startTime.uptimeNanoseconds
    let elapsed = Double(nanoTime / 100) / 1_000_000.0
    return elapsed
  }

  open override var supportedInterfaceOrientations: UIInterfaceOrientationMask{
    get {
      if self.isLandscape {
        return .landscapeLeft
      } else {
        return .portraitUpsideDown
      }
    }
  }

  func captureScreen(_ small:Bool) -> UIImage? {
    let size = self.view.bounds.size
    var scale = UIScreen.main.scale
    if small {
      scale = 1.0
    }
    UIGraphicsBeginImageContextWithOptions(size, true, scale);
    self.view.drawHierarchy(in: self.view.bounds, afterScreenUpdates: true);
    let snapshotImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return snapshotImage;
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
            case "removeorange", "hideorange", "andwait":
              if hasOrange && webView != nil {
                webView!.isHidden = false
                hasOrange = false
              }
            default:
              self.log("Unknown command option: \(messageParts[i])")
          }
        }
      }
      switch message {
      case "addorange", "setorange", "showorange", "orange": addOrange(id:id)
      case "battery":
        UIDevice.current.isBatteryMonitoringEnabled = true
        sendMessage(id: id, message: "OK", data:"\(UIDevice.current.batteryLevel)")
      case "clearcache": clearCache(id:id)
      case "closebrowser", "stopbrowser": closeBrowser(id:id)
      case "exec":
        if data != nil {
          execScript(id:id, script:data!)
        } else {
          sendMessage(id:id, message:"ERROR", data:"Missing script for exec")
        }
      case "exit": exit(0)
      case "landscape":
        if !isLandscape {
          isLandscape = true
          UIViewController.attemptRotationToDeviceOrientation()
        }
      case "navigate":
        if data != nil {
          navigate(id:id, to:data!)
        } else {
          sendMessage(id:id, message:"ERROR", data:"Missing URL for navigation")
        }
      case "osversion":
        sendMessage(id: id, message: "OK", data:"\(UIDevice.current.systemVersion)")
      case "portrait":
        if isLandscape {
          isLandscape = false
          UIViewController.attemptRotationToDeviceOrientation()
        }
      case "removeorange", "hideorange":
        if hasOrange && webView != nil {
          webView!.isHidden = false
          hasOrange = false
        } else {
          self.sendMessage(id:id, message:"ERROR")
        }
      case "setuseragent":
        if data != nil {
          setUserAgent(id:id, ua:data!)
        } else {
          sendMessage(id:id, message:"ERROR", data:"Missing User agent string")
        }
      case "screenshot": screenShot(id:id, small:true)
      case "screenshotbig": screenShot(id:id, small:false)
      case "screenshotbigjpeg": screenShotJpeg(id:id, small:false)
      case "screenshotjpeg": screenShotJpeg(id:id, small:true)
      case "startbrowser": startBrowser(id:id)
      case "startvideo": startVideo(id:id)
      case "stopvideo": stopVideo(id:id)
      case "deletevideo":
        deleteVideo()
        self.sendMessage(id:id, message:"OK")
      case "getvideo": getVideo(id:id)
      default:
        sendMessage(id:id, message:"ERROR", data:"Unknown command: \(message)")
      }
    }
  }
  
  /*************************************************************************************
                                  browser operations
   *************************************************************************************/
  func clearCache(id:String) {
    let websiteDataTypes = NSSet(array: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeCookies,
                                         WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage, WKWebsiteDataTypeWebSQLDatabases,
                                         WKWebsiteDataTypeIndexedDBDatabases, WKWebsiteDataTypeOfflineWebApplicationCache])
    HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
    WKWebsiteDataStore.default().removeData(ofTypes: websiteDataTypes as! Set<String>, modifiedSince: Date.distantPast) {
      self.sendMessage(id:id, message:"OK")
    }
  }
  
  func startBrowser(id:String) {
    UIScreen.main.brightness = 0.0
    closeWebView()
    self.view.backgroundColor = UIColor(red: 222.0/255.0, green: 100.0/255.0, blue: 13.0/255.0, alpha: 1.0)
    startTime = DispatchTime.now()
    webView = WKWebView()
    webView!.frame = self.view.bounds
    self.view.addSubview(webView!)
    webView!.isHidden = true
    webView!.loadHTMLString(startPage, baseURL: URL(string: "http://www.webpagetest.org"))
    hasOrange = true
    webView!.navigationDelegate = self
    webView!.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
    webView!.addObserver(self, forKeyPath: #keyPath(WKWebView.title), options: .new, context: nil)
    webView!.addObserver(self, forKeyPath: #keyPath(WKWebView.isLoading), options: .new, context: nil)
    title = "iWptBrowser"
    sendMessage(id:id, message:"OK")
  }
  
  func closeWebView() {
    self.view.backgroundColor = UIColor.black
    if webView != nil {
      webView!.navigationDelegate = nil
      webView!.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
      webView!.removeObserver(self, forKeyPath: #keyPath(WKWebView.title))
      webView!.removeObserver(self, forKeyPath: #keyPath(WKWebView.isLoading))
      webView!.removeFromSuperview()
      webView = nil
    }
  }

  func closeBrowser(id:String) {
    closeWebView()
    hasOrange = false
    isActive = false
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
      webView!.isHidden = false
      hasOrange = false
      isActive = true
      webView!.load(URLRequest(url: URL(string:url)!))
      sendMessage(id:id, message:"OK")
    } else {
      sendMessage(id:id, message:"ERROR", data:"Browser not started")
    }
  }
  
  func setUserAgent(id:String, ua:String) {
    if webView != nil {
      webView!.customUserAgent = ua
      sendMessage(id:id, message:"OK")
    } else {
      sendMessage(id:id, message:"ERROR", data:"Browser not started")
    }
  }
  
  func addOrange(id:String) {
    if webView != nil {
      webView!.isHidden = true
      hasOrange = true
      self.sendMessage(id:id, message:"OK")
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
          returned = "\(error!.localizedDescription)"
        }
        if result != nil {
          let type = type(of:result!)
          self.log("\(type): \(result!)")
          let is_json = JSONSerialization.isValidJSONObject(result!)
          if is_json {
            do {
              let json = try JSONSerialization.data(withJSONObject: result!)
              returned = String(data: json, encoding:.utf8)!
            } catch {
            }
          }
          if returned.characters.count == 0 {
            returned = "\(result!)"
          }
        }
        self.sendMessage(id:id, message:ok, data:returned)
      }
    } else {
      sendMessage(id:id, message:"ERROR", data:"Browser not started")
    }
  }
  
  func screenShot(id:String, small:Bool) {
    let image = captureScreen(small)
    if image != nil {
      let png = UIImagePNGRepresentation(image!)
      if png != nil {
        let encoded = png?.base64EncodedString()
        if encoded != nil {
          sendMessage(id:id, message:"OK!encoded", data:encoded!)
          return
        }
      }
    }
    sendMessage(id:id, message:"ERROR")
  }

  func screenShotJpeg(id:String, small:Bool) {
    let image = captureScreen(small)
    if image != nil {
      let png = UIImageJPEGRepresentation(image!, 0.75)
      if png != nil {
        let encoded = png?.base64EncodedString()
        if encoded != nil {
          sendMessage(id:id, message:"OK!encoded", data:encoded!)
          return
        }
      }
    }
    sendMessage(id:id, message:"ERROR")
  }

  /*************************************************************************************
                                  Video Capture
   *************************************************************************************/
  func startVideo(id:String) {
    if videoCapture == nil {
      deleteVideo()
      videoCapture = ASScreenRecorder()
      videoCapture!.videoURL = videoUrl
      videoCapture!.bitrate = 8000000
      videoCapture!.scale = 1.0
      videoCapture!.startRecording()
      sendMessage(id:id, message:"OK")
    } else {
      sendMessage(id:id, message:"ERROR")
    }
  }
  
  func stopVideo(id:String) {
    if videoCapture != nil {
      videoCapture!.stopRecording() {
        self.videoCapture = nil
        self.sendMessage(id:id, message:"OK")
      }
    } else {
      sendMessage(id:id, message:"ERROR")
    }
  }
  
  func deleteVideo() {
    do {
      try FileManager.default.removeItem(at: videoUrl!)
    } catch _ {
    }
  }
  
  func getVideo(id:String) {
    let queue = DispatchQueue(label: "org.webpagetest.message")
    queue.async {
      do {
        let attr = try FileManager.default.attributesOfItem(atPath: self.videoUrl!.path) as NSDictionary
        let filesize = attr.fileSize()
        let file = fopen(self.videoUrl!.path, "r")
        if file != nil {
          var dataSent = 0
          let chunkSize = 4096
          let readBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
          var done = false
          self.sendMessageSync(id: "", message: "StartVideo", data: "\(filesize)")
          repeat {
            let count = fread(readBuffer, 1, chunkSize, file)
            if count > 0 {
              dataSent += count
              let data = NSData(bytes: readBuffer, length: count)
              self.sendMessageSync(id: "", message:"VideoData!encoded", data: data.base64EncodedString())
            } else {
              done = true
            }
          } while !done
          self.sendMessageSync(id: "", message: "EndVideo", data: "\(filesize)")
          self.sendMessageSync(id: id, message: "OK", data: "\(dataSent) bytes sent of \(filesize) bytes")
          fclose(file)
        } else {
          self.sendMessageSync(id: id, message: "ERROR", data:"")
        }
      } catch let err {
        self.log("Error getting video: \(err)")
        self.sendMessageSync(id: id, message: "ERROR", data:"")
      }
    }
  }
  
  /*************************************************************************************
                                  Webview interfaces
   *************************************************************************************/
  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    if isActive && keyPath != nil {
      switch keyPath! {
      case "estimatedProgress":
        if webView != nil {
          sendNotification(message:"page.progress", data:"\(webView!.estimatedProgress)")
        }
      case "title":
        if webView != nil && webView!.title != nil {
          title = webView!.title!
          sendNotification(message:"page.title", data: webView!.title!)
        }
      case "loading":
        if webView != nil {
          if webView!.isLoading {
            sendNotification(message: "page.loading")
          } else {
            sendNotification(message: "page.loadingFinished")
          }
        }
      default:
        self.log("Unexpected observation: \(keyPath!)")
      }
    }
  }
  
  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    if isActive {
      self.sendNotification(message: "page.didCommit")
    }
  }
  
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    if isActive {
      self.sendNotification(message: "page.didStartProvisionalNavigation")
    }
  }
  
  func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
    if isActive {
      self.sendNotification(message: "page.didReceiveServerRedirectForProvisionalNavigation")
    }
  }
  
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    if isActive {
      self.sendNotification(message: "page.didFinish")
    }
  }
  
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError: Error) {
    if isActive {
      title = withError.localizedDescription
      self.sendNotification(message: "page.didFail", data:"\(withError.localizedDescription)")
    }
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError: Error) {
    if isActive {
      title = withError.localizedDescription
      self.sendNotification(message: "page.didFailProvisionalNavigation", data:"\(withError.localizedDescription)")
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if isActive {
      let url = navigationAction.request.url!
      if navigationAction.targetFrame == nil || navigationAction.targetFrame!.isMainFrame {
        self.sendNotification(message: "page.navigateStart", data:url.absoluteString)
      } else {
        self.sendNotification(message: "page.navigateFrameStart", data:url.absoluteString)
      }
    }
    decisionHandler(.allow)
  }
  
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    if isActive {
      self.sendNotification(message: "browser.terminated")
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
    let timestamp = self.timestamp()
    let queue = DispatchQueue(label: "org.webpagetest.message")
    queue.async {
      var str = "\(timestamp)\t\(id)"
      if id.characters.count > 0 {
        str += ":"
      }
      var msg = message
      var rawData = data
      if data.range(of: "\t") != nil || data.range(of: "\n") != nil {
        msg += "!encoded"
        rawData = rawData.base64Encoded()!
      }
      str += msg
      if rawData.characters.count > 0 {
        str += "\t"
        str += rawData
      }
      str += "\n"
      self.sendMessageAsync(str)
    }
  }

  func sendMessageSync(id:String, message:String, data:String) {
    let timestamp = self.timestamp()
    var str = "\(timestamp)\t\(id)"
    if id.characters.count > 0 {
      str += ":"
    }
    var msg = message
    var rawData = data
    if data.range(of: "\t") != nil || data.range(of: "\n") != nil {
      msg += "!encoded"
      rawData = rawData.base64Encoded()!
    }
    str += msg
    if rawData.characters.count > 0 {
      str += "\t"
      str += rawData
    }
    str += "\n"
    self.sendMessageAsync(str)
  }

  func sendMessageAsync(_ message:String) {
    if clientSocket != nil {
      if message.characters.count < 200 {
        self.log(">> \(message)")
      } else {
        let end = message.index(message.startIndex, offsetBy:200)
        self.log(">> \(message.substring(to: end)) ...")
      }
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
        count += 1
        self.log("Agent #\(count) connected")
        clientSocket = client
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
      try socket.setBlocking(mode: true)
      try socket.setReadTimeout(value: 10000)
    } catch let err {
      self.log("\(id): Socket setup error: \(err)")
    }
    repeat {
      do {
        let str = try socket.readString()
        if (str != nil) {
          self.receivedRawData(id:id, str:str!)
        }
      } catch let err {
        self.log("Pump Socket read exception: \(err)")
        cont = socket.isConnected && !socket.remoteConnectionClosed
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
}
