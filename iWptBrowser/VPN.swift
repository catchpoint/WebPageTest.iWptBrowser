//
//  vpnBridge.swift
//  iWptBrowser
//
//  Created by Patrick Meenan on 9/21/17.
//  Copyright © 2017 WebPageTest LLC. All rights reserved.
//

import Foundation
import NetworkExtension

/*
 Server as a TCP bridge between the local network extension and remote USBMux connection
 since both require making outbound connections.
 */
public class VPN {
  var startTime = Date().timeIntervalSinceReferenceDate
  var localSocket:Socket?
  var remoteSocket:Socket?
  var vpn:NETunnelProviderManager?
  var notificationObserver:NSObjectProtocol?

  public init(localPort: Int, remotePort: Int) {
    // Start background threads to listen for connections from either side
    let queue1 = DispatchQueue(label: "org.webpagetest.vpnlocallisten", attributes: .concurrent)
    queue1.async {
      self.socketListenThread(port:localPort, isLocal: true)
    }
    let queue2 = DispatchQueue(label: "org.webpagetest.vpnremotelisten", attributes: .concurrent)
    queue2.async {
      self.socketListenThread(port:remotePort, isLocal: false)
    }
    configureVpnEntry()
    notificationObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.NEVPNStatusDidChange, object: nil, queue: nil) {
      notification in
      self.log("received NEVPNStatusDidChangeNotification")
      self.updateStatus()
    }
  }
  
  func connect() -> Bool {
    if vpn != nil {
      do {
        self.log("Connecting")
        try vpn!.connection.startVPNTunnel()
        return true
      } catch let err {
        self.log("VPN connect error: \(err)")
      }
    }
    return false
  }

  func disconnect() {
    if vpn != nil {
      self.log("Disconnecting")
      vpn!.connection.stopVPNTunnel()
    }
  }

  func configureVpnEntry() {
    NETunnelProviderManager.loadAllFromPreferences() { loadedManagers, error in
      if let vpnEntries = loadedManagers {
        for entry in vpnEntries {
          if self.vpn == nil {
            self.vpn = entry
          } else {
            entry.removeFromPreferences() { error in }
          }
        }
      }
      if self.vpn == nil {
        self.vpn = NETunnelProviderManager()
      }
      if self.vpn != nil {
        self.vpn!.loadFromPreferences() { error in
          if error != nil {
            self.log ("Error Loading Preferences: \(error!.localizedDescription)")
          } else {
            self.log("Loaded Preferences")
          }
          self.vpn!.localizedDescription = "Reverse Tether"
          let provider = NETunnelProviderProtocol()
          provider.serverAddress = "USB"
          provider.disconnectOnSleep = true
          provider.providerBundleIdentifier = "org.webpagetest.browser.tether"
          self.vpn!.protocolConfiguration = provider
          self.vpn!.isEnabled = true
          self.vpn!.isOnDemandEnabled = true
          self.vpn!.saveToPreferences() { error in
            if error != nil {
              self.log("Error Saving Preferences")
              print (error!)
            } else {
              self.log("Saved Preferences")
            }
            self.updateStatus()
          }
        }
      }
    }
  }

  func updateStatus() {
    var statusText = "Unknown"
    if vpn != nil {
      switch vpn!.connection.status {
      case NEVPNStatus.connected: statusText = "Connected"
      case NEVPNStatus.connecting: statusText = "Connecting"
      case NEVPNStatus.disconnected: statusText = "Disconnected"
      case NEVPNStatus.disconnecting: statusText = "Disconnecting"
      default: statusText = "Unknown"
      }
    }
    self.log("VPN status change to \(statusText)")
  }

  func socketListenThread(port:Int, isLocal: Bool) {
    let name = isLocal ? "local" : "remote"
    self.log("Running \(name) VPN socket thread")
    do {
      let socket = try Socket.create()
      socket.readBufferSize = 65535
      try socket.listen(on: port)
      var count = 0
      repeat {
        let client = try socket.acceptClientConnection()
        count += 1
        self.log("\(name) VPN socket #\(count) connected")
        let queue = DispatchQueue(label: "org.webpagetest.vpn\(name)socket\(count)", attributes: .concurrent)
        queue.async {
          self.pumpSocket(socket:client, id:count, isLocal:isLocal)
        }
      } while true
    } catch let err {
      self.log("Socket exception: \(err)")
    }
  }
  
  func pumpSocket(socket:Socket, id: Int, isLocal: Bool) {
    let name = isLocal ? "local" : "remote"
    var cont = true
    do {
      try socket.setBlocking(mode: true)
      try socket.setReadTimeout(value: 10000)
    } catch let err {
      self.log("\(id): \(name) VPN Socket setup error: \(err)")
    }
    var one: Int = 1
    let size = UInt32(MemoryLayout.size(ofValue: one))
    setsockopt(socket.socketfd, IPPROTO_TCP, TCP_NODELAY, &one, size)
    if isLocal {
      localSocket = socket
    } else {
      remoteSocket = socket
    }
    
    // Pump data from one socket into the other or drop data on the floor
    // and close the connection if the other side isn't connected.
    if let buff = NSMutableData(capacity: 10000) {
      repeat {
        do {
          let rc = try socket.read(into: buff)
          if rc > 0 {
            if isLocal {
              if remoteSocket != nil {
                do {
                  self.log(">>> \(buff.length) bytes")
                  try remoteSocket!.write(from: buff)
                } catch let err {
                  self.log("Pump \(name) VPN Socket write exception: \(err)")
                  remoteSocket!.close()
                  cont = false
                }
              }
            } else {
              if localSocket != nil {
                do {
                  self.log("<<< \(buff.length) bytes")
                  try localSocket!.write(from: buff)
                } catch let err {
                  self.log("Pump \(name) VPN Socket write exception: \(err)")
                  localSocket!.close()
                  cont = false
                }
              }
            }
          } else {
            self.log("Pump \(name) VPN Socket read error: \(rc)")
            cont = socket.isConnected && !socket.remoteConnectionClosed
          }
        } catch let err {
          self.log("Pump \(name) VPN Socket read exception: \(err)")
          cont = socket.isConnected && !socket.remoteConnectionClosed
        }
      } while cont
    }

    socket.close()
    self.log("\(id): \(name) Socket closed")
  }

  func log(_ message: String) {
    NSLog("VpnBridge (\(self.timestamp())): \(message)")
  }
  
  func timestamp() -> Double {
    let now = Date().timeIntervalSinceReferenceDate
    let elapsed = Double(round((now - startTime) * 1_000_000) / 1_000_000)
    return elapsed
  }
}

