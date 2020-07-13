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
            return (data: track.response.body as Data?, response: track.response.urlResponse, error: track.response.error)
        case .multipleFound:
            throw TurntableError.multipleTracksFound
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
