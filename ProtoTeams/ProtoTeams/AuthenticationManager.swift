//
//  AuthenticationManager.swift
//  ProtoTeams
//
//  Created by Mac on 26/5/20.
//  Copyright © 2020 Mobila. All rights reserved.
//

import Foundation
import MSAL
import MSGraphClientSDK

// Implement the MSAuthenticationProvider interface so
// this class can be used as an auth provider for the Graph SDK
class AuthenticationManager: NSObject, MSGraphClientSDK.MSAuthenticationProvider {

    // Implement singleton pattern
    static let instance = AuthenticationManager()

    private let publicClient: MSAL.MSALPublicClientApplication?
    private let appId: String
    var userId: String?
    private let graphScopes: Array<String>

    private override init() {
        // Get app ID and scopes from AuthSettings.plist
        let bundle = Bundle.main
        let authConfigPath = bundle.path(forResource: "AuthSettings", ofType: "plist")!
        let authConfig = NSDictionary(contentsOfFile: authConfigPath)!

        self.appId = authConfig["AppId"] as! String
        self.graphScopes = authConfig["GraphScopes"] as! Array<String>

        do {
            // Create the MSAL client
            try self.publicClient = MSAL.MSALPublicClientApplication(clientId: self.appId)
        } catch {
            print("Error creating MSAL public client: \(error)")
            self.publicClient = nil
        }
    }

    // Required function for the MSAuthenticationProvider interface
    func getAccessToken(for authProviderOptions: MSGraphClientSDK.MSAuthenticationProviderOptions!, andCompletion completion: ((String?, Error?) -> Void)!) {
        getTokenSilently(completion: completion)
    }

    public func getTokenInteractively(parentView: UIViewController, completion: @escaping(_ accessToken: String?, Error?) -> Void) {
        let keyWindow = UIApplication.shared.connectedScenes.filter({$0.activationState == .foregroundActive}).map({$0 as? UIWindowScene}).compactMap({$0}).first?.windows.filter({$0.isKeyWindow}).first
        let rvc = keyWindow?.rootViewController
        
        let webParameters = MSAL.MSALWebviewParameters(parentViewController: rvc!) //parentView
        let interactiveParameters = MSAL.MSALInteractiveTokenParameters(scopes: self.graphScopes,
                                                                   webviewParameters: webParameters)
        interactiveParameters.promptType = MSAL.MSALPromptType.selectAccount

        // Call acquireToken to open a browser so the user can sign in
        publicClient?.acquireToken(with: interactiveParameters, completionBlock: {
            [weak self]
            (result: MSAL.MSALResult?, error: Error?) in
            guard let self = self else {
                print("no self")
                completion(nil, error)
                return
            }
            guard let tokenResult = result, error == nil else {
                print("Error getting token interactively: \(String(describing: error))")
                completion(nil, error)
                return
            }
            self.userId = result?.account.identifier
            print("Got token interactively: \(tokenResult.accessToken)")
            completion(tokenResult.accessToken, nil)
        })
    }

    public func getTokenSilently(completion: @escaping(_ accessToken: String?, Error?) -> Void) {
        // Check if there is an account in the cache
        var userAccount: Any?  //MSAL.MSALAccount?

        do {
            userAccount = try publicClient?.allAccounts().first
        } catch {
            print("Error getting account: \(error)")
        }

        if (userAccount != nil) {
            // Attempt to get token silently
            let silentParameters = MSAL.MSALSilentTokenParameters(scopes: self.graphScopes, account: userAccount as! MSALAccount)  //userAccount!
            publicClient?.acquireTokenSilent(with: silentParameters, completionBlock: {
                [weak self]
                (result: MSAL.MSALResult?, error: Error?) in
                guard let self = self else {
                    print("no self")
                    completion(nil, error)
                    return
                }
                guard let tokenResult = result, error == nil else {
                    print("Error getting token silently: \(String(describing: error))")
                    completion(nil, error)
                    return
                }
                self.userId = result?.account.identifier
                print("Got token silently: \(tokenResult.accessToken)")
                completion(tokenResult.accessToken, nil)
            })
        } else {
            print("No account in cache")
            completion(nil, NSError(domain: "AuthenticationManager",
                                    code: MSAL.MSALError.interactionRequired.rawValue, userInfo: nil))
        }
    }

    public func signOut() -> Void {
        do {
            // Remove all accounts from the cache
            let accounts = try publicClient?.allAccounts()

            try accounts!.forEach({
                (account: MSAL.MSALAccount) in
                try publicClient?.remove(account)
            })
        } catch {
            print("Sign out error: \(String(describing: error))")
        }
    }
}
