//
//  Turntable.swift
//  Vinyl
//
//  Created by Rui Peres on 12/02/2016.
//  Copyright © 2016 Velhotes. All rights reserved.
//

import Foundation

enum TurntableError: Error {
    
    case trackNotFound
    case noRecordingPath
}

public typealias Plastic = [[String: Any]]
typealias RequestCompletionHandler =  (Data?, URLResponse?, Error?) -> Void

public final class Turntable: URLSession {
    
    var errorHandler: ErrorHandler = DefaultErrorHandler()
    fileprivate let turntableConfiguration: TurntableConfiguration
    fileprivate var player: Player?
    public var recorder: Recorder?
    public var recordingSession: URLSession?
    public var requestMatcherRegistry: RequestMatcherRegistry
    fileprivate let operationQueue: OperationQueue
    
    public init(
        configuration: TurntableConfiguration,
        requestMatcherTypes: [RequestMatcherType],
        delegateQueue: OperationQueue? = nil,
        urlSession: URLSession? = nil) {
        
        turntableConfiguration = configuration
        if let delegateQueue = delegateQueue {
            operationQueue = delegateQueue
        } else {
            operationQueue = OperationQueue()
            operationQueue.maxConcurrentOperationCount = 1
        }

        self.requestMatcherRegistry = RequestMatcherRegistry(types: requestMatcherTypes)

        if configuration.recodingEnabled {
            recorder = Recorder(
                wax: Wax(tracks: []),
                recordingPath: configuration.recordingPath,
                requestMatcherRegistry: requestMatcherRegistry)
        }
        recordingSession = urlSession ?? URLSession.shared

        super.init()
    }
    
    public convenience init(
        vinyl: Vinyl,
        requestMatcherTypes: [RequestMatcherType],
        turntableConfiguration: TurntableConfiguration = TurntableConfiguration(),
        delegateQueue: OperationQueue? = nil,
        urlSession: URLSession? = nil) {

        self.init(
            configuration: turntableConfiguration,
            requestMatcherTypes: requestMatcherTypes,
            delegateQueue: delegateQueue,
            urlSession: urlSession)
        player = Turntable.createPlayer(with: vinyl, configuration: turntableConfiguration)
    }
    
    public convenience init(
        vinylName: String,
        baseVinylName: String? = nil,
        requestMatcherTypes: [RequestMatcherType],
        bundle: Bundle = testingBundle(),
        turntableConfiguration: TurntableConfiguration = TurntableConfiguration(),
        delegateQueue: OperationQueue? = nil,
        urlSession: URLSession? = nil) {
        
        let plastic = Turntable.createPlastic(vinyl: vinylName, bundle: bundle, recordingMode: turntableConfiguration.recordingMode)

        var combinedPlastic = plastic
        var baseVinyl: Vinyl?
        if let baseVinylName = baseVinylName,
            let basePlastic = Turntable.createPlastic(vinyl: baseVinylName, bundle: bundle, recordingMode: turntableConfiguration.recordingMode, isBaseVinyl: true) {

            baseVinyl = Vinyl(plastic: basePlastic)
            if combinedPlastic != nil {
                combinedPlastic?.append(contentsOf: basePlastic)
            } else {
                combinedPlastic = basePlastic
            }
        }

        let vinyl = Vinyl(plastic: combinedPlastic ?? [])
        self.init(
            vinyl: vinyl,
            requestMatcherTypes: requestMatcherTypes,
            turntableConfiguration: turntableConfiguration,
            delegateQueue: delegateQueue,
            urlSession: urlSession)

        let recordingVinyl = Vinyl(plastic: plastic ?? [])
        switch turntableConfiguration.recordingMode {
        case .missingVinyl, .missingTracks:
            let recordingPath = self.recordingPath(
                fromConfiguration: turntableConfiguration,
                vinylName: vinylName,
                bundle: bundle)
            recorder = Recorder(
                wax: Wax(vinyl: recordingVinyl, baseVinyl: baseVinyl),
                recordingPath: recordingPath,
                requestMatcherRegistry: requestMatcherRegistry)
        default:
            recorder = nil
            recordingSession = nil
        }
    }
    
    deinit {
        stopRecording()
    }
    
    public func stopRecording() {
        guard let recorder = recorder else {
            return
        }
        
        do {
            try recorder.persist()
        }
        catch TurntableError.noRecordingPath {
            fatalError("💣 no path was configured for saving the recording.")
        }
        catch let error as NSError {
            fatalError("💣 we couldn't save the recording: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private methods

    fileprivate func playVinyl<URLSessionTask: URLSessionTaskType>(request: URLRequest, fromData bodyData: Data? = nil, completionHandler: @escaping RequestCompletionHandler) throws -> URLSessionTask {
        guard let player = player else {
            fatalError("Did you forget to load the Vinyl? 🎶")
        }

        let completion = try player.playTrack(for: transform(request: request, bodyData: bodyData))

        return URLSessionTask {
            self.operationQueue.addOperation {
                // Set cookies
                if request.httpShouldHandleCookies, 
                   let cookieStorage = self.configuration.httpCookieStorage, 
                   let httpResponse = completion.response as? HTTPURLResponse, 
                   let headerFields = httpResponse.allHeaderFields as? [String: String], 
                   let url = httpResponse.url {
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
                    cookieStorage.setCookies(cookies, for: url, mainDocumentURL: request.mainDocumentURL)
                }

                completionHandler(completion.data, completion.response, completion.error)
            }
        }
    }

    fileprivate func recordingHandler(request: URLRequest, fromData bodyData: Data? = nil, completionHandler: @escaping RequestCompletionHandler) -> RequestCompletionHandler {
        guard let recorder = recorder else {
            fatalError("No recording started.")
        }
        
        return {
            data, response, error in
            
            recorder.saveTrack(with: self.transform(request: request, bodyData: bodyData), urlResponse: response as? HTTPURLResponse, body: data, error: error)
            
            self.operationQueue.addOperation {
                completionHandler(data, response, error)
            }
        }
    }
    
    fileprivate func transform(request: URLRequest, bodyData: Data? = nil) -> URLRequest {
        guard let bodyData = bodyData else {
            return request
        }

        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            fatalError("💥 Houston, we have a problem 🚀")
        }

        mutableRequest.httpBody = bodyData

        return mutableRequest as URLRequest
    }

    fileprivate func recordingPath(fromConfiguration configuration: TurntableConfiguration, vinylName: String, bundle: Bundle) -> String? {
        if let recordingPath = configuration.recordingPath {
            return recordingPath
        }
        
        return bundle.resourceURL?.appendingPathComponent(vinylName).appendingPathExtension("json").path
    }
    
    public override var delegate: URLSessionDelegate? {
        return recordingSession?.delegate
    }
}

// MARK: - NSURLSession methods

extension Turntable {
    
    public override var configuration: URLSessionConfiguration {
        if let session = recordingSession {
            return session.configuration
        } else {
            return URLSessionConfiguration.default
        }
    }
    
    public override func dataTask(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> Foundation.URLSessionDataTask {
        let request = URLRequest(url: url)
        print("Request for: " + (url.absoluteString))
        return dataTask(with: request, completionHandler: completionHandler)
    }
    
    public override func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> Foundation.URLSessionDataTask {
        
        do {
            return try playVinyl(request: request, completionHandler: completionHandler) as URLSessionDataTask
        }
        catch TurntableError.trackNotFound {
            print("Track not found for: " + (request.url?.absoluteString ?? "(no url)"))
            if let session = recordingSession {

                print("Performing network request")
                return session.dataTask(with: request, completionHandler: recordingHandler(request: request, completionHandler: completionHandler))
            }
            else {
                errorHandler.handleTrackNotFound(request, playTracksUniquely: turntableConfiguration.playTracksUniquely)
            }
        }
        catch {
            errorHandler.handleUnknownError()
        }
        
        return URLSessionDataTask(completion: {})
    }
    
    public override func uploadTask(with request: URLRequest, from bodyData: Data?, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> Foundation.URLSessionUploadTask {
        
        do {
            return try playVinyl(request: request, fromData: bodyData, completionHandler: completionHandler) as URLSessionUploadTask
        }
        catch TurntableError.trackNotFound {
            if let session = recordingSession {
                return session.uploadTask(with: request, from: bodyData, completionHandler: recordingHandler(request: request, fromData: bodyData, completionHandler: completionHandler))
            }
            else {
                errorHandler.handleTrackNotFound(request, playTracksUniquely: turntableConfiguration.playTracksUniquely)
            }
        }
        catch {
            errorHandler.handleUnknownError()
        }
        
        return URLSessionUploadTask(completion: {})
    }
    
    public override func invalidateAndCancel() {
        // We won't do anything for
    }
}

// MARK: - Loading Methods

extension Turntable {
    
    public func load(vinyl vinylName: String,  bundle: Bundle = testingBundle()) {
        let plastic = Turntable.createPlastic(vinyl: vinylName, bundle: bundle, recordingMode: turntableConfiguration.recordingMode)
        let vinyl = Vinyl(plastic: plastic ?? [])
        player = Turntable.createPlayer(with: vinyl, configuration: turntableConfiguration)

        switch turntableConfiguration.recordingMode {
        case .missingVinyl where plastic == nil, .missingTracks:
            recorder = Recorder(
                wax: Wax(vinyl: vinyl), recordingPath: recordingPath(fromConfiguration: turntableConfiguration, vinylName: vinylName, bundle: bundle), requestMatcherRegistry: requestMatcherRegistry)
        default:
            recorder = nil
            recordingSession = nil
        }
    }
    
    public func load(cassette cassetteName: String,  bundle: Bundle = testingBundle()) {
        
        let vinyl = Vinyl(plastic: Turntable.createPlastic(cassette: cassetteName, bundle: bundle))
        player = Turntable.createPlayer(with: vinyl, configuration: turntableConfiguration)
    }
    
    public func load(vinyl: Vinyl) {
        player = Turntable.createPlayer(with: vinyl, configuration: turntableConfiguration)
    }
}

// MARK: - Bootstrap methods

extension Turntable {
    
    fileprivate static func createPlayer(with vinyl: Vinyl, configuration: TurntableConfiguration) -> Player {
        
        let trackMatchers = configuration.trackMatchers(for: vinyl)
        return Player(vinyl: vinyl, trackMatchers: trackMatchers)
    }
    
    fileprivate static func createPlastic(cassette cassetteName: String, bundle: Bundle) -> Plastic {
        
        guard let cassette: [String: AnyObject] = loadJSON(from: bundle, fileName: cassetteName) else {
            fatalError("💣 Cassette file \"\(cassetteName)\" not found 😩")
        }
        
        guard let plastic = cassette["interactions"] as? Plastic else {
            fatalError("💣 We couldn't find the \"interactions\" key in your cassette 😩")
        }
        
        return plastic
    }
    
    public static func createPlastic(vinyl vinylName: String, bundle: Bundle, recordingMode: RecordingMode, isBaseVinyl: Bool = false) -> Plastic? {

        if isBaseVinyl {
            return loadPlastic(vinylName: vinylName, bundle: bundle)
        }
        switch recordingMode {
        case .missingVinyl:
            return nil
        case .missingTracks, .none:
            return loadPlastic(vinylName: vinylName, bundle: bundle)
        }
    }

    fileprivate static func loadPlastic(vinylName: String, bundle: Bundle) -> Plastic? {
        if let plastic: Plastic = loadJSON(from: bundle, fileName: vinylName) {
            return plastic
        } else {
            fatalError("💣 Vinyl file \"\(vinylName)\" not found 😩")
        }
    }


}
