//
//  AppDelegate.swift
//  ProtoTeams
//
//  Created by Mac on 26/5/20.
//  Copyright © 2020 Mobila. All rights reserved.
//

import UIKit
import MSAL

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
//        setupMSALLogger()
        return true
    }
    
//    func setupMSALLogger() {
//        // The MSAL Logger should be set as early as possible in the app launch sequence, before any MSAL
//        // requests are made.
//
//        MSAL.MSALGlobalConfig.loggerConfig.setLogCallback { (logLevel, message, containsPII) in
//
//            // If PiiLoggingEnabled is set YES, this block will potentially contain sensitive information (Personally Identifiable Information), but not all messages will contain it.
//            // containsPII == YES indicates if a particular message contains PII.
//            // You might want to capture PII only in debug builds, or only if you take necessary actions to handle PII properly according to legal requirements of the region
//            if let displayableMessage = message {
//                if (!containsPII) {
//                    #if DEBUG
//                    // NB! This sample uses print just for testing purposes
//                    // You should only ever log to NSLog in debug mode to prevent leaking potentially sensitive information
//                    print(displayableMessage)
//                    #endif
//                }
//            }
//        }
//    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

//    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
//
//        guard let sourceApplication = options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String else {
//            return false
//        }
//
//        return MSAL.MSALPublicClientApplication.handleMSALResponse(url, sourceApplication: sourceApplication)
//    }
}
