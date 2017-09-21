//
//  PacketTunnelProvider.swift
//  tether
//
//  Created by Patrick Meenan on 9/21/17.
//  Copyright © 2017 WebPageTest LLC. All rights reserved.
//

import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
  var startTime = Date().timeIntervalSinceReferenceDate
  var socket:Socket?

  func log(_ message: String) {
    NSLog("iWptBrowser tether (\(self.timestamp())): \(message)")
  }
  
  func timestamp() -> Double {
    let now = Date().timeIntervalSinceReferenceDate
    let elapsed = Double(round((now - startTime) * 1_000_000) / 1_000_000)
    return elapsed
  }

  override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
    self.log("Starting tether")
    do {
      socket = try Socket.create()
      if socket != nil {
        socket!.readBufferSize = 65535
        try socket!.connect(to: "127.0.0.1", port:19220)
        completionHandler(nil)
      }
    } catch let err {
      self.log("Socket exception: \(err)")
      completionHandler(err)
    }
  }
  
  override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    self.log("Stopping tether")
    if socket != nil {
      socket!.close()
      socket = nil
    }
    completionHandler()
  }
  
  override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
      // Add code here to handle the message.
      if let handler = completionHandler {
          handler(messageData)
      }
  }
  
  override func sleep(completionHandler: @escaping () -> Void) {
      // Add code here to get ready to sleep.
      completionHandler()
  }
  
  override func wake() {
      // Add code here to wake up.
  }
}
