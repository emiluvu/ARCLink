//
//  FieldwireAPIClient.swift
//  ARCLink
//

import Foundation

struct FieldwireTaskLive: Codable, Identifiable {
    let id: String
    let name: String?
    let title: String?
    let statusID: String?
    let ownerUserID: Int?
    let teamID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case title
        case statusID = "status_id"
        case ownerUserID = "owner_user_id"
        case teamID = "team_id"
    }

    var displayTitle: String {
        title ?? name ?? "Untitled Fieldwire Task"
    }
}

// ============================================================
// PROJECT MODEL
// ============================================================

struct FieldwireProject: Codable, Identifiable {
    let id: String
    let name: String
}

// ============================================================
// STATUS MODEL
// ============================================================

struct FieldwireStatus: Codable, Identifiable {
    let id: String
    let name: String
    let ordinal: Int?
    let color: String?
}

// ============================================================
// JWT RESPONSE MODEL
// ============================================================

struct FieldwireJWTResponse: Codable {

    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

// ============================================================
// API CLIENT
// ============================================================

final class FieldwireAPIClient {

    private let baseURL = "https://app.fieldwire.com/api/v3"

    // Long-lived API token from Fieldwire
    private let apiToken: String

    init(token: String) {
        self.apiToken = token
    }

    // ============================================================
    // STEP 1:
    // Exchange API token for temporary JWT access token
    // ============================================================

    private func generateAccessToken() async throws -> String {

        guard let url = URL(
            string: "https://client-api.super.fieldwire.com/api_keys/jwt"
        ) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)

        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        let body = [
            "api_token": apiToken
        ]

        request.httpBody = try JSONSerialization.data(
            withJSONObject: body
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        print(
            "JWT response:",
            String(data: data, encoding: .utf8) ?? "No readable response"
        )

        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {

            let bodyText = String(
                data: data,
                encoding: .utf8
            ) ?? ""

            throw NSError(
                domain: "FieldwireAuth",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: bodyText
                ]
            )
        }

        let jwtResponse = try JSONDecoder().decode(
            FieldwireJWTResponse.self,
            from: data
        )

        return jwtResponse.accessToken
    }

    // ============================================================
    // FETCH PROJECTS
    // ============================================================

    func fetchProjects() async throws -> [FieldwireProject] {

        let accessToken = try await generateAccessToken()

        guard let url = URL(
            string: "\(baseURL)/projects"
        ) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)

        request.httpMethod = "GET"

        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        
        request.setValue(
            "2024-10-01",
            forHTTPHeaderField: "Fieldwire-Version"
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        print(
            "Projects response:",
            String(data: data, encoding: .utf8) ?? "No readable response"
        )

        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {

            let bodyText = String(
                data: data,
                encoding: .utf8
            ) ?? ""

            throw NSError(
                domain: "FieldwireAPI",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: bodyText
                ]
            )
        }

        return try JSONDecoder().decode(
            [FieldwireProject].self,
            from: data
        )
    }

    // ============================================================
    // FETCH STATUSES
    // ============================================================

    func fetchStatuses(
        projectID: String
    ) async throws -> [FieldwireStatus] {

        let accessToken = try await generateAccessToken()

        guard let url = URL(
            string: "\(baseURL)/projects/\(projectID)/statuses"
        ) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)

        request.httpMethod = "GET"

        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        
        request.setValue(
            "2024-10-01",
            forHTTPHeaderField: "Fieldwire-Version"
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        print(
            "Statuses response:",
            String(data: data, encoding: .utf8) ?? "No readable response"
        )

        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {

            let bodyText = String(
                data: data,
                encoding: .utf8
            ) ?? ""

            throw NSError(
                domain: "FieldwireAPI",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: bodyText
                ]
            )
        }

        return try JSONDecoder().decode(
            [FieldwireStatus].self,
            from: data
        )
    }
    
    func fetchTasks(projectID: String) async throws -> [FieldwireTaskLive] {
        let accessToken = try await generateAccessToken()

        guard let url = URL(string: "\(baseURL)/projects/\(projectID)/tasks") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2024-10-01", forHTTPHeaderField: "Fieldwire-Version")
        request.setValue("100", forHTTPHeaderField: "Fieldwire-Per-Page")

        let (data, response) = try await URLSession.shared.data(for: request)

        print("Tasks response:", String(data: data, encoding: .utf8) ?? "No readable response")

        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "FieldwireAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: bodyText]
            )
        }

        return try JSONDecoder().decode([FieldwireTaskLive].self, from: data)
    }
}
