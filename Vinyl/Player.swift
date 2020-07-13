//
//  Player.swift
//  Vinyl
//
//  Created by David Rodrigues on 16/02/16.
//  Copyright © 2016 Velhotes. All rights reserved.
//

import Foundation

enum SeekResult {
    case found(track: Track)
    case notFound
    case multipleFound(tracks: [Track])
}

struct Player {
    
    let vinyl: Vinyl
    let trackMatchers: [TrackMatcher]
    
    private func seekTrack(for request: Request)  -> SeekResult {

        let matchingTracks = vinyl.tracks.filter {
            track in
            return trackMatchers.all { matcher in matcher.matchable(track: track, for: request) }
        }

        switch matchingTracks.count {
        case 0:
            return .notFound
        case 1:
            return .found(track: matchingTracks[0])
        default:
            return .multipleFound(tracks: matchingTracks)
        }
    }
    
    func playTrack(for request: Request) throws -> (data: Data?, response: URLResponse?, error: Error?) {

        switch self.seekTrack(for: request) {
        case .found(let track):
            print("Playing vinyl for: " + (request.url?.absoluteString ?? "(no url)"))
            return track.asNetworkResponse()
        case .multipleFound(let tracks):
            print("Warning: Found multiple tracks for request \(request)")
            return tracks[0].asNetworkResponse()

        case .notFound:
            throw TurntableError.trackNotFound
        }
    }
    
    func trackExists(for request: Request) -> Bool {
        if case .found = self.seekTrack(for: request) {
            return true
        }
        
        return false
    }
}

private extension Track {
    func asNetworkResponse() -> (data: Data?, response: URLResponse?, error: Error?) {
        (
        data: response.body as Data?,
        response: response.urlResponse,
        error: response.error)
    }
}
