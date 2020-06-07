//
//  GraphManager.swift
//  ProtoTeams
//
//  Created by Mac on 26/5/20.
//  Copyright © 2020 Mobila. All rights reserved.
//

import Foundation
import MSGraphClientSDK
import MSGraphClientModels

class GraphManager {

    // Implement singleton pattern
    static let instance = GraphManager()

    private let client: MSHTTPClient?

    private init() {
        client = MSClientFactory.createHTTPClient(with: AuthenticationManager.instance)
    }

    public func getMe(completion: @escaping(MSGraphUser?, Error?) -> Void) {
        // GET /me
        let meRequest = NSMutableURLRequest(url: URL(string: "\(MSGraphBaseURL)/me")!)
        let meDataTask = MSURLSessionDataTask(request: meRequest, client: self.client, completion: {
            (data: Data?, response: URLResponse?, graphError: Error?) in
            guard let meData = data, graphError == nil else {
                completion(nil, graphError)
                return
            }

            do {
                // Deserialize response as a user
                let user = try MSGraphUser(data: meData)
                completion(user, nil)
            } catch {
                completion(nil, error)
            }
        })

        // Execute the request
        meDataTask?.execute()
    }

    func startVideoCall(startDate: String?, endDate: String?, subject: String?, completion: @escaping(Data?, Error?) -> Void) {
        let baseURLString = "https://graph.microsoft.com/v1.0/"
        if let url = URL(string: "\(baseURLString)me/onlineMeetings") {
            let urlRequest = NSMutableURLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd/MM/yyyy HH:mm"
            var meeting = OnlineMeeting() //
//            var meet = MSGraphOnlineMeeting().
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

                let task = MSURLSessionDataTask(request: urlRequest, client: self.client) {
                    data, response, graphError in
                    guard let data = data, graphError == nil else {
                        completion(nil, graphError)
                        return
                    }
                    completion(data, nil)
                }
                task?.execute()
            } catch {
                print("error: \(error.localizedDescription)")
            }
        }
    }
}
