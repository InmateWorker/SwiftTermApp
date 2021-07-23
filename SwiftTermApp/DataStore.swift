//
//  DataStore.swift
//  testMasterDetail
//
//  Created by Miguel de Icaza on 4/26/20.
//  Copyright © 2020 Miguel de Icaza. All rights reserved.
//

import Foundation
import Combine

// TODO: maybe the `type` could be an enum with Swift 5.5?
class Key: Codable, Identifiable {
    var id: UUID
    var type: KeyType = .rsa(4096)
    var name: String = ""
    
    // This stores the private key as pasted by the user, or if it is a type = .ecdsa(inSecureEnclave:true) the tag for the key in the KeyChain
    var privateKey: String = ""
    // This stores the public key as pasted by the user
    var publicKey: String = ""
    var passphrase: String = ""
    var keyTag: String = ""
    
    public init (id: UUID = UUID(), type: KeyType = .rsa(4096), name: String = "", privateKey: String = "", publicKey: String = "", passphrase: String = "")
    {
        self.id = id
        self.type = type
        self.name = name
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.passphrase = passphrase
    }
    
    /// If the key is stored in the KeyChain, returns the handle
    public func getKeyHandle () -> SecKey? {
        switch type  {
            case .ecdsa(inEnclave: true):
                let query: [String:Any] = [
                  kSecClass as String: kSecClassKey,
                  kSecAttrApplicationTag as String: privateKey,
                  kSecReturnRef as String: true
                ]
                var result: CFTypeRef!
                
                if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess && result != nil {
                    return (result as! SecKey)
                }
            return nil
        default:
            return nil
        }
    }
    
    ///
    public func getPublicKeyAsData () -> Data {
        let values = publicKey.split (separator: " ")
        if values.count > 2 {
            if let decoded =  Data (base64Encoded: String (values [1])) {
                return decoded
            }
        }
        return Data()
    }
}

/// Represents a host we connect to, the data structure we save, and keep at runtime
/// Most properties are used at connection time, and a handful can be changed at runtime:
///
/// Properties that can be changed at runtime:
/// - style:
/// - background
/// - backspaceAsControlH
///
/// Possibly should add; Font and FontSize
class Host: Codable, Identifiable {
    internal init(id: UUID = UUID(), alias: String = "", hostname: String = "", backspaceAsControlH: Bool = false, port: Int = 22, usePassword: Bool = true, username: String = "", password: String = "", hostKind: String = "", environmentVariables: [String] = [], startupScripts: [String] = [], sshKey: UUID? = nil, style: String = "", background: String = "", lastUsed: Date = Date.distantPast) {
        self.id = id
        self.alias = alias
        self.hostname = hostname
        self.backspaceAsControlH = backspaceAsControlH
        self.port = port
        self.usePassword = usePassword
        self.username = username
        self.password = password
        self.hostKind = hostKind
        self.environmentVariables = environmentVariables
        self.startupScripts = startupScripts
        self.sshKey = sshKey
        self.style = style
        self.background = background
        self.lastUsed = lastUsed
    }
    
    var id = UUID()
    var alias: String = ""
    var hostname: String = ""
    var backspaceAsControlH: Bool = false
    var port: Int = 22
    var usePassword: Bool = true
    var username: String = ""
    var password: String = ""
    var hostKind: String = ""
    
    /// Environment variables to pass on the connection
    var environmentVariables: [String] = []
    var startupScripts: [String] = []
    
    // This is the UUID of the key registered with the app
    var sshKey: UUID?
    
    /// The current color theme style name, if the style is "" it means "use the default"
    var style: String = ""
    
    /// The values are `default` to pick the value from settings, "" to use a solid color, or the name of a live background
    var background: String = ""
    
    var lastUsed: Date = Date.distantPast
    
    func summary() -> String {
        hostname + (style != "" ? ", \(style)" : "")
    }
}

struct KnownHost: Identifiable {
    var host: String
    var keyType: String
    var key: String
    var rest: String
    var id: UUID
}

class DataStore: ObservableObject {
    static let testKey1 = Key (id: UUID(), type: .rsa (1024), name: "Fake Legacy Key", privateKey: "", publicKey: "", passphrase: "")
    static let testKey2 = Key (id: UUID(), type: .rsa (4096), name: "Fake 2020 iPhone Key", privateKey: "", publicKey: "", passphrase: "")
    
    static let testUuid2 = UUID ()
    
    var defaults: UserDefaults?
    
    @Published var hosts: [Host] = [
       Host(alias: "Dummy MacPro",         hostname: "192.168.86.220", lastUsed: Date ()),
       //Host(alias: "Dummy Raspberri Pi",   hostname: "raspberry.tirania.org", lastUsed: Date ()),
       //Host(alias: "Dummy MacBook",        hostname: "road.tirania.org", usePassword: false, sshKey: DataStore.testKey1.id),
       //Host(alias: "Dummy Old Vax",        hostname: "oldvax.tirania.org",usePassword: false, sshKey: DataStore.testKey2.id),
       //Host(alias: "Dummy Old DECStation", hostname: "decstation.tirania.org"),
    ]
    
    @Published var keys: [Key] = [
        testKey1, testKey2
    ]
    
    @Published var knownHosts: [KnownHost] = []
    
    /// Event raised when the properties that can be changed on a live connection have changed
    var runtimeVisibleChanges = PassthroughSubject<Host,Never> ()
    
    let hostsArrayKey = "hostsArray"
    let keysArrayKey = "keysArray"
    public var knownHostsPath: String
    
    init ()
    {
        func getKnownHostsPath () -> String {
            let fm = FileManager.default
            guard let p = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return "known_hosts"
            }
            try? fm.createDirectory (at: p, withIntermediateDirectories: true, attributes: nil)
            return p.path + "/known_hosts"
        }
        self.knownHostsPath = getKnownHostsPath()
        
        defaults = UserDefaults (suiteName: "SwiftTermApp")
        let decoder = JSONDecoder ()
        if let d = defaults {
            if let data = d.data(forKey: hostsArrayKey) {
                if let h = try? decoder.decode ([Host].self, from: data) {
                    hosts = h
                }
            }
            if let data = d.data(forKey: keysArrayKey) {
                if let k = try? decoder.decode ([Key].self, from: data) {
                    keys = k
                }
            }
        }
        loadKnownHosts()
    }
    
    // Saves the data store
    func saveState ()
    {
        guard let d = defaults else {
            return
        }
        let coder = JSONEncoder ()
        if let hostData = try? coder.encode(hosts) {
            d.set (hostData, forKey: hostsArrayKey)
        }
        if let keyData = try? coder.encode (keys) {
            d.set (keyData, forKey: keysArrayKey)
        }
        
        saveKnownHosts ()
    }
    
    // Records the new host in the data store
    func save (host: Host)
    {
        if let idx = hosts.firstIndex (where: { $0.alias == host.alias }) {
            hosts.remove(at: idx)
            hosts.insert(host, at: idx)
        } else {
            hosts.append(host)
        }
        saveState ()
    }

    func used (host: Host)
    {
        if let f = hosts.firstIndex(where: {$0.id == host.id}){
            hosts [f].lastUsed = Date()
            saveState()
        }
    }
    // Records the new host in the data store
    func save (key: Key)
    {
        if let idx = keys.firstIndex(where: { $0.id == key.id }) {
            keys.remove(at: idx)
            keys.insert(key, at: idx)
        } else {
            keys.append(key)
        }
        saveState ()
    }

    func hasHost (withAlias: String) -> Bool
    {
        hosts.contains { $0.alias == withAlias }
    }
    
    func hostHasValidKey (host: Host) -> Bool {
        
        let c = keys.contains { $0.id == host.sshKey }
        return c
    }

    func updateGuess (for target: Host, to guess: String)
    {
        for i in 0..<hosts.count {
            if hosts [i].id == target.id {
                hosts [i].hostKind = guess
            }
        }
    }

    // This for now returns the name, but if it is ambiguous, it could return a hash or something else
    func getSshDisplayName (forHost: Host) -> String {
        if let k = keys.first(where: { $0.id == forHost.sshKey }) {
            return k.name
        }
        return "none"
    }
    
    // Returns the most recent 3 values
    func recentIndices () -> [Int]
    {
        var res: [Int] = []
        let sorted = hosts.sorted(by: {a, b in a.lastUsed > b.lastUsed })
        for x in sorted.prefix(3) {
            if let idx = hosts.firstIndex(where: {$0.id == x.id }) {
                res.append(idx)
            }
        }
        return res
    }
    
    func loadKnownHosts ()
    {
        guard let content = try? String (contentsOfFile: knownHostsPath) else {
            return
        }
        
        func makeRecord (part: [Substring]) -> KnownHost? {
            guard part.count >= 3 else {
                return nil
            }
            return KnownHost (host: String (part [0]),
                           keyType: String (part [1]),
                           key: String (part[2]),
                           rest: part [3...].map { String ($0) }.joined(separator: " "),
                           id: UUID ())
        }
        knownHosts.removeAll()
        for line in content.split(separator: "\n") {
            guard let record = makeRecord(part: line.split (separator: " ")) else { continue }
            knownHosts.append(record)
        }
    }
    
    func saveKnownHosts () {
        var res = ""
        for record in knownHosts {
            res += "\(record.host) \(record.keyType) \(record.key) \(record.rest)\n"
        }
        try? res.write(toFile: knownHostsPath, atomically: true, encoding: .utf8)
    }
    
    static var shared: DataStore = DataStore()
}
