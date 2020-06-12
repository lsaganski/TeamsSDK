//
//  AuthenticationManager.swift
//  HubCall
//
//  Created by Mac on 10/6/20.
//  Copyright © 2020 Mobila. All rights reserved.
//

import Foundation
import MSAL
import MSGraphClientSDK

// Implement the MSAuthenticationProvider interface so
// this class can be used as an auth provider for the Graph SDK
class AuthenticationManager: NSObject, MSAuthenticationProvider {

    // Implement singleton pattern
    static let instance = AuthenticationManager()

    private let publicClient: MSALPublicClientApplication?
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
            try self.publicClient = MSALPublicClientApplication(clientId: self.appId)
        } catch {
            print("Error creating MSAL public client: \(error)")
            self.publicClient = nil
        }
    }

    // Required function for the MSAuthenticationProvider interface
    func getAccessToken(for authProviderOptions: MSAuthenticationProviderOptions!, andCompletion completion: ((String?, Error?) -> Void)!) {
        getTokenSilently(completion: completion)
    }

    public func getTokenInteractively(parentView: UIViewController, completion: @escaping(_ accessToken: String?, Error?) -> Void) {
        let webParameters = MSALWebviewParameters(parentViewController: parentView)
        let interactiveParameters = MSALInteractiveTokenParameters(scopes: self.graphScopes,
                                                                   webviewParameters: webParameters)
        interactiveParameters.promptType = MSALPromptType.selectAccount

        // Call acquireToken to open a browser so the user can sign in
        publicClient?.acquireToken(with: interactiveParameters, completionBlock: {
            (result: MSALResult?, error: Error?) in
            guard let tokenResult = result, error == nil else {
                print("Error getting token interactively: \(String(describing: error))")
                completion(nil, error)
                return
            }

            self.userId = result?.account.identifier

            print("Got token interactively: \(tokenResult.accessToken)")
            UserDefaults().set(tokenResult.accessToken, forKey: "token")
            UserDefaults().set(result?.account.identifier, forKey: "userId")
            completion(tokenResult.accessToken, nil)
        })
    }

    public func getTokenSilently(completion: @escaping(_ accessToken: String?, Error?) -> Void) {
        let token = UserDefaults().string(forKey: "token")
        self.userId = UserDefaults().string(forKey: "userId")

        if (token != nil) {
            completion(token, nil)
        } else {
            print("No account in cache")
            completion(nil, NSError(domain: "AuthenticationManager",
                                    code: MSALError.interactionRequired.rawValue, userInfo: nil))
        }
    }

    public func signOut() -> Void {
        do {
            UserDefaults().removeObject(forKey: "token")
            UserDefaults().removeObject(forKey: "userId")
        } catch {
            print("Sign out error: \(String(describing: error))")
        }
    }
}
