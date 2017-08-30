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
  var buffer_in = ""
  
  func log(_ message: String) {
    NSLog("iWptBrowser: \(message)")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    let queue = DispatchQueue(label: "org.webpagetest.socketlisten", attributes: .concurrent)
    queue.async {
      self.socketListenThread()
    }
  }
  
  func handleMessage(_ message:String) {
    self.log("Message: \(message)")
  }
  
  func socketListenThread() {
    self.log("Running socket thread")
    do {
      let socket = try Socket.create()
      try socket.listen(on: 19222)
      var count = 0
      repeat {
        let client = try socket.acceptClientConnection()
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
    var data = Data(capacity: 65535)
    var cont = true
    repeat {
      do {
        let length = try socket.read(into: &data)
        if length > 0 {
          self.receivedRawData(id:id, length:length, data:data)
        }
      } catch let err {
        self.log("\(id): Socket Read error: \(err)")
        cont = false
      }
    } while cont
    socket.close()
  }
  
  func receivedRawData(id:Int, length:Int, data:Data) {
    self.log("\(id): Received \(length) bytes")
    if let str = String(data:data, encoding: .utf8) {
      for (_, ch) in str.characters.enumerated() {
        if ch == "\n" {
          if buffer_in.characters.count > 0 {
            DispatchQueue.main.async {
              self.handleMessage(self.buffer_in)
            }
            self.buffer_in = ""
          }
        } else {
          buffer_in.append(ch)
        }
      }
    }
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
  }


}

