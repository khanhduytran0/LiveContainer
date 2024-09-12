//
//  LCMDMServer.swift
//  LCMDMServer
//
//  Created by s s on 2024/8/21.
//

import Foundation
import Network

struct LCMDMServer {
    public static var instance : LCMDMServer? = nil
    
    public static var mdmData : Data? = nil
    private let listener : NWListener
    
    init() throws {
        self.listener = try NWListener(using: .tcp, on: .any)
    }
    
    func start(_ continuation: CheckedContinuation<Void, Never>?) {
        // Define the state update handler
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let continuation = continuation {
                    continuation.resume()
                }
                
            case .failed(let error):
                NSLog("[LC] Server failed with error: \(error)")
                if let continuation = continuation {
                    continuation.resume()
                }
            default:
                break
            }
        }

        // Define the connection handler
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)

            // Set up a receive handler to read data
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, context, isComplete, error in
                if let data = data, !data.isEmpty {
                    
                    // Create the HTTP response
                    let response : String
                    if let mdmData = LCMDMServer.mdmData {
                        response = """
                        HTTP/1.1 200 OK
                        Content-Type: application/x-apple-aspen-config
                        Content-Length: \(mdmData.count)

                        \(String(data: mdmData, encoding: .utf8)!)
                        """
                    } else {
                        response = """
                        HTTP/1.1 404
                        """
                    }
                    
                    // Send the response back to the client
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ sendError in
                        if let sendError = sendError {
                            NSLog("[LC] Failed to send response: \(sendError)")
                        }
                        connection.cancel()
                    }))
                } else {
                    if let error = error {
                        NSLog("[LC] Error receiving data: \(error)")
                    }
                    connection.cancel()
                }
            }
        }

        // Start the listener
        listener.start(queue: .global())
    }
    
    // start the server if needed
    func getPort() -> UInt16 {
        if let port = listener.port {
            return port.rawValue
        } else {
            return 0
        }
    }
    
    func getState() -> NWListener.State {
        return listener.state
    }
}
