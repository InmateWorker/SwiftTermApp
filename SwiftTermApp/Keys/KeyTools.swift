//
//  KeyTools.swift
//  SwiftTermApp
//
//  Created by Miguel de Icaza on 6/13/21.
//  Copyright © 2021 Miguel de Icaza. All rights reserved.
//

import Foundation

class KeyTools {
    static func generateKey (type: KeyType, keyTag: String, comment: String, passphrase: String, inSecureEnclave: Bool)-> Key?

    {
        switch type {
        case .ecdsa:
            let access =
            SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .privateKeyUsage,
                nil)!   // Ignore error

            let attributes: [String: Any]
            
            if inSecureEnclave {
                attributes = [
                kSecAttrKeyType as String:            kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits as String:      256,
                kSecAttrTokenID as String:            kSecAttrTokenIDSecureEnclave,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String:     true,
                    kSecAttrApplicationTag as String:
                        keyTag.data(using: .utf8)! as CFData,
                    kSecAttrAccessControl as String:   access
                ]
                ]
            } else {
                attributes = [
                kSecAttrKeyType as String:            kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits as String:      256,
                ]
            }
            
            var error: Unmanaged<CFError>? = nil
            guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
                print ("Oops: \(error.debugDescription)")
                return nil
            }
            let publicKey = SecKeyCopyPublicKey  (privateKey)
            
            guard let publicText = SshUtil.generateSshPublicKey(k: publicKey!, comment: comment) else {
                print ("Could not produce the public key")
                return nil
            }
            let privateText: String
            if inSecureEnclave {
                privateText = keyTag
            } else {
                guard let p = SshUtil.generateSshPrivateKey(pub: publicKey!, priv: privateKey, comment: comment) else {
                    print ("Could not produce the private key")
                    return nil
                }
                privateText = p
            }
            return Key(id: UUID(),
                       type: inSecureEnclave ? "se-ecdsa" : "ecdsa",
                       name: comment,
                       privateKey: privateText,
                       publicKey: publicText,
                       passphrase: "")
            
            // TODO: not yet implemented
        case .rsa(let bits):
            if let (priv, pub) = try? CC.RSA.generateKeyPair(2048) {
                print ("\(priv) \(pub) \(bits)")
            }
            break
        }
        return nil
    }

    static func haveSecureEnclaveKey (keyTag: String) -> Bool {
        let lookupKey: [String:Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecReturnRef as String: true]
        
        var item: CFTypeRef?
        return SecItemCopyMatching (lookupKey as CFDictionary, &item) == errSecSuccess && item != nil
    }
}
