//
//  Recorder.swift
//  Vinyl
//
//  Created by Michael Brown on 07/08/2016.
//  Copyright © 2016 Velhotes. All rights reserved.
//

import Foundation

public enum ExcludedRequestType {
    case host(String)
    case hostOtherThan(String)
    case custom(ExcludedRequest)
}

public protocol ExcludedRequest {
    func shouldExclude(request: Request) -> Bool
}

public final class Recorder {
    var wax: Wax
    let recordingPath: String?
    let requestMatcherRegistry: RequestMatcherRegistry
    let excludedRequestTypes: [ExcludedRequestType]

    public init(wax: Wax,
                recordingPath: String?,
                requestMatcherRegistry: RequestMatcherRegistry,
                excludedRequestTypes: [ExcludedRequestType]) {
        self.wax = wax
        self.recordingPath = recordingPath
        self.requestMatcherRegistry = requestMatcherRegistry
        self.excludedRequestTypes = excludedRequestTypes
    }

    private static func excludedRequest(for excludedRequestType: ExcludedRequestType) -> ExcludedRequest {
        switch excludedRequestType {
        case .host(let host):
            return HostExcludedRequest(host: host)
        case .custom(let customRequestMatcher):
            return customRequestMatcher
        case .hostOtherThan(let host):
            return HostOtherThanExcludedRequest(host: host)
        }
    }
}

extension Recorder {
    func saveTrack(with request: Request, response: Response) {
        let shouldExclude = excludedRequestTypes.reduce(false, { result, exclude in
            result || Recorder.excludedRequest(for: exclude).shouldExclude(request: request)
        })
        if !shouldExclude {
            wax.add(
                track: Track(request: request, response: response),
                registry: requestMatcherRegistry)
        }
    }
    
    func saveTrack(with request: Request, urlResponse: HTTPURLResponse?, body: Data? = nil, error: Error? = nil) {
        let response = Response(urlResponse: urlResponse, body: body, error: error)
        saveTrack(with: request, response: response)
    }
}

extension Recorder {
    
    func persist() throws {
        guard let recordingPath = recordingPath else {
            throw TurntableError.noRecordingPath
        }

        let fileManager = FileManager.default
        guard fileManager.createFile(atPath: recordingPath, contents: nil, attributes: nil) == true,
            let file = FileHandle(forWritingAtPath: recordingPath) else {
            return
        }
        
        let jsonWax = wax.tracks.map {
            $0.encodedTrack()
        }
        
        let data = try JSONSerialization.data(withJSONObject: jsonWax, options: .prettyPrinted)
        file.write(data)
        file.synchronizeFile()
        
        print("Vinyl recorded to: \(recordingPath)")
    }
}

private struct HostExcludedRequest: ExcludedRequest {
    let host: String
    func shouldExclude(request: Request) -> Bool {
        request.url?.host == host
    }

}

private struct HostOtherThanExcludedRequest: ExcludedRequest {
    let host: String
    func shouldExclude(request: Request) -> Bool {
        request.url?.host != host
    }

}
