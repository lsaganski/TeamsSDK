//
//  MainViewController.swift
//  ProtoTeams
//
//  Created by Mac on 26/5/20.
//  Copyright © 2020 Mobila. All rights reserved.
//

import Foundation
import UIKit
import MSGraphClientModels
import MSGraphClientSDK

class MainViewController: UIViewController {

    @IBOutlet weak var userProfilePhoto: UIImageView!
    @IBOutlet weak var userDisplayName: UILabel!
    @IBOutlet weak var userEmail: UILabel!
    
    private let spinner = SpinnerViewController()
    
    override func viewDidLoad() {
        navigationItem.hidesBackButton = true

//        self.spinner.start(container: self)

       // Get the signed-in user
//        self.userProfilePhoto.image = UIImage(imageLiteralResourceName: "DefaultUserPhoto")

//        GraphManager.instance.getMe {
//            (user: MSGraphUser?, error: Error?) in
//
//            DispatchQueue.main.async {
//                self.spinner.stop()
//
//                guard let currentUser = user, error == nil else {
//                    print("Error getting user: \(String(describing: error))")
//                    return
//                }
//
//                // Set display name
//                self.userDisplayName.text = currentUser.displayName ?? "Mysterious Stranger"
//                self.userDisplayName.sizeToFit()
//
//                // AAD users have email in the mail attribute
//                // Personal accounts have email in the userPrincipalName attribute
//                self.userEmail.text = currentUser.mail ?? currentUser.userPrincipalName ?? ""
//                self.userEmail.sizeToFit()
//            }
//        }
        
        MSTUIApplication.sharedInstance()?.initialize()

    }
    
    @IBAction func signOut() {
//        AuthenticationManager.instance.signOut()
//        self.performSegue(withIdentifier: "userSignedOut", sender: nil)
    }
    
    @IBAction func videoCall() {
        spinner.start(container: self)
        
        let startDateStr = "28/05/2020 05:45"
        let endDateStr = "28/05/2020 06:00"
        let subject = "Teste 001"
        GraphManager.instance.startVideoCall(startDate: startDateStr, endDate: endDateStr, subject: subject) {
            [weak self] data, error in
            guard let self = self else {
                print("no self for you")
                return
            }
            DispatchQueue.main.async {
                self.spinner.stop()
            }
            guard let data = data else {
                print("error: \(error)")
                return
            }
            print("response: \(String(data: data, encoding: .utf8))")
            let decoder = JSONDecoder()
            let parsedData = try! decoder.decode(OnlineMeeting.self, from: data)
            if let strUrl = parsedData.joinWebUrl, strUrl.count > 0 {
                var error: NSError?
                MSTUIApplication.sharedInstance()?.joinMeeting(with: strUrl, participantName: "Leo", error: &error)

                if error != nil {
                    print(error)
                    self.throwAlert(error:error!)
                }
            }
        }
    }
    
    func throwAlert(error: NSError) {
            let alert = UIAlertController(title: "SDK Status", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            UIApplication.shared.keyWindow?.rootViewController?.present(alert, animated: true, completion: nil)
    }

}

struct AudioConferencing: Codable {
    var tollNumber: String?
    var tollFreeNumber: String?
    var ConferenceId: String?
    var dialinUrl: String?
}

struct ChatInfo: Codable {
    var threadId: String?
    var messageId: String?
    var replyChainMessageId: String?
}

struct MSALUser: Codable {
    var id: String?
    var displayName: String?
}

struct MSALIdentity: Codable {
    var user: MSALUser?
}

struct Organizer: Codable {
    var identity: MSALIdentity?
    var upn: String?
}

struct Participant: Codable {
    var organizer: Organizer?
}

struct OnlineMeeting: Codable {
    var audioConferencing: AudioConferencing?
    var chatInfo: ChatInfo?
    var creationDateTime: String?
    var startDateTime: String?
    var endDateTime: String?
    var id: String?
    var joinWebUrl: String?
    var participants: Participant?
    var subject: String?
}
