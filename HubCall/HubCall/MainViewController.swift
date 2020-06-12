//
//  MainViewController.swift
//  HubCall
//
//  Created by Mac on 10/6/20.
//  Copyright © 2020 Mobila. All rights reserved.
//

import Foundation
import UIKit

class MainViewController: UIViewController {
    
    private let spinner = SpinnerViewController()

    override func viewDidLoad() {
        MicrosoftTeamsSDK.sharedInstance().initialize()
    }
    
    @IBAction func onClickConnect(sender: UIButton) {
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
                MicrosoftTeamsSDK.sharedInstance().joinMeeting(with: strUrl, participantName: "Leo", error: &error)
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
    
    @IBAction func signOut() {
       AuthenticationManager.instance.signOut()
       self.performSegue(withIdentifier: "userSignedOut", sender: nil)
    }
}
