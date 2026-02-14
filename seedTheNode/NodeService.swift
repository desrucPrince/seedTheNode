//
//  NodeService.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import Foundation
import Observation

@Observable
final class NodeService {

    // MARK: - State

    var isOnline = false
    var isLoading = false
    var lastError: String?

    var hostname = "10.0.0.204"
    var port = 3000

    // Health data
    var nodeName: String?
    var lastChecked: Date?
    var trackCount = 0
    var storage: StorageInfo?
    var ipfsInfo: IPFSInfo?

    // Tracks
    var tracks: [Track] = []

    var baseURL: String {
        "http://\(hostname):\(port)"
    }

    // MARK: - Health Check

    func checkHealth() async {
        isLoading = true
        lastError = nil

        do {
            let health: HealthResponse = try await get("/api/health")
            isOnline = true
            nodeName = health.node
            trackCount = health.trackCount
            storage = health.storage
            ipfsInfo = health.ipfs
            lastChecked = Date()
            lastError = nil
        } catch {
            isOnline = false
            lastError = friendlyError(error)
        }

        isLoading = false
    }

    // MARK: - Tracks

    func fetchTracks() async {
        do {
            tracks = try await get("/api/tracks")
        } catch {
            lastError = friendlyError(error)
        }
    }

    func createTrack(title: String, artistName: String) async -> Track? {
        struct Body: Encodable { let title: String; let artistName: String }
        do {
            let track: Track = try await post("/api/tracks", body: Body(title: title, artistName: artistName))
            tracks.insert(track, at: 0)
            trackCount += 1
            return track
        } catch {
            lastError = friendlyError(error)
            return nil
        }
    }

    func deleteTrack(_ id: String) async -> Bool {
        do {
            let _: DeleteResponse = try await delete("/api/tracks/\(id)")
            tracks.removeAll { $0.id == id }
            trackCount -= 1
            return true
        } catch {
            lastError = friendlyError(error)
            return false
        }
    }

    func uploadAudio(trackId: String, fileURL: URL, mimeType: String = "audio/mpeg") async -> Track? {
        do {
            let track: Track = try await uploadFile(
                "/api/tracks/\(trackId)/upload",
                fileURL: fileURL,
                fieldName: "audio",
                mimeType: mimeType
            )
            if let idx = tracks.firstIndex(where: { $0.id == trackId }) {
                tracks[idx] = track
            }
            return track
        } catch {
            lastError = friendlyError(error)
            return nil
        }
    }

    // MARK: - Networking Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func uploadFile<T: Decodable>(
        _ path: String,
        fileURL: URL,
        fieldName: String,
        mimeType: String
    ) async throws -> T {
        let url = URL(string: "\(baseURL)\(path)")!
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body = Data()
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func checkHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NodeError.badResponse(code)
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if let nodeError = error as? NodeError {
            return nodeError.localizedDescription
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "Connection timed out — is the API running?"
            case .cannotConnectToHost: return "Cannot reach \(hostname) — check WiFi"
            case .notConnectedToInternet: return "No internet connection"
            default: return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Errors

enum NodeError: LocalizedError {
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): "Bad response from node (HTTP \(code))"
        }
    }
}

// MARK: - API Models

struct HealthResponse: Decodable {
    let status: String
    let node: String
    let timestamp: String
    let message: String
    let trackCount: Int
    let storage: StorageInfo
    let ipfs: IPFSInfo
}

struct StorageInfo: Decodable {
    let totalGB: Double
    let usedGB: Double
    let freeGB: Double
}

struct IPFSInfo: Decodable {
    let peerId: String?
    let agentVersion: String?
    let peers: Int
}

struct Track: Decodable, Identifiable {
    let id: String
    let title: String
    let artistName: String
    let ipfsCid: String?
    let createdAt: String
    let updatedAt: String
    let versionCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title
        case artistName = "artist_name"
        case ipfsCid = "ipfs_cid"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case versionCount = "version_count"
    }
}

struct DeleteResponse: Decodable {
    let deleted: Bool
}

// MARK: - Data Extension

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
