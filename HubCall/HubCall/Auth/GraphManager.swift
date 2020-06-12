//
//  GraphManager.swift
//  HubCall
//
//  Created by Mac on 10/6/20.
//  Copyright © 2020 Mobila. All rights reserved.
//

import Foundation
import MSGraphClientSDK
import MSGraphClientModels

class GraphManager: NSObject {

    static let instance = GraphManager()
    var token: String?

    override private init() {
        super.init()
        AuthenticationManager.instance.getTokenSilently() { [weak self]
            token, error in
            guard let self = self else {
                return
            }
            if token != nil {
                self.token = token
            }
        }
    }

    public func getMe(completion: @escaping(MSGraphUser?, Error?) -> Void) {
        // GET /me
//        let meRequest = NSMutableURLRequest(url: URL(string: "\(MSGraphBaseURL)/me")!)
//        let meDataTask = MSURLSessionDataTask(request: meRequest, client: self.client, completion: {
//            (data: Data?, response: URLResponse?, graphError: Error?) in
//            guard let meData = data, graphError == nil else {
//                completion(nil, graphError)
//                return
//            }
//
//            do {
//                // Deserialize response as a user
//                let user = try MSGraphUser(data: meData)
//                completion(user, nil)
//            } catch {
//                completion(nil, error)
//            }
//        })
//
//        // Execute the request
//        meDataTask?.execute()
    }

    func startVideoCall(startDate: String?, endDate: String?, subject: String?, completion: @escaping(Data?, Error?) -> Void) {
        let baseURLString = "https://graph.microsoft.com/v1.0/"
        if let url = URL(string: "\(baseURLString)me/onlineMeetings") {
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd/MM/yyyy HH:mm"
            var meeting = OnlineMeeting()
            let startDateAux = dateFormatter.date(from: startDate ?? "")
            let endDateAux = dateFormatter.date(from: endDate ?? "")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSXXX"
            if let startDateAux = startDateAux {
                let startDateStr = dateFormatter.string(from: startDateAux)
                meeting.startDateTime = startDateStr
            }
            if let endDateAux = endDateAux {
                let endDateStr = dateFormatter.string(from: endDateAux)
                meeting.endDateTime = endDateStr
            }
            meeting.subject = subject ?? ""
            var user = MSALUser() // MSGraphIdentity()
            user.id = AuthenticationManager.instance.userId!
            var identity = MSALIdentity() // MSGraphIdentitySet()
            identity.user = user
//            identity.device = nil
//            identity.application = nil
            var organizer = Organizer() // MSGraphMeetingParticipantInfo()
            organizer.identity = identity
//            organizer.upn = ""
            var participants = Participant() // MSGraphMeetingParticipants()
            participants.organizer = organizer
//            participants.attendees = []
            meeting.participants = participants

            do {
                let meetingData = try JSONEncoder().encode(meeting) // meeting.   //getSerializedData()
                urlRequest.httpBody = meetingData
                urlRequest.addValue("Bearer \(self.token ?? "")", forHTTPHeaderField: "Authorization")
                urlRequest.addValue("graph.microsoft.com", forHTTPHeaderField: "Host")
                let config = URLSessionConfiguration.default
                let session = URLSession(configuration: config, delegate: self as! URLSessionDelegate, delegateQueue: OperationQueue.main)
                let task = session.dataTask(with: urlRequest) {[weak self]
                    data, response, error in
                    guard let data = data else {
                        print("\(error)")
                        completion(nil, error)
                        return
                    }
                    print(String(data: data, encoding: .utf8))
                    completion(data, nil)
                }
                
                task.resume()
            } catch {
                print("error: \(error.localizedDescription)")
            }
        }
    }
}

extension GraphManager: URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
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
