import Foundation

struct ConnectionFailure: Identifiable, Equatable, Sendable {
    var id: UUID { profileID }
    let profileID: UUID
    let connectionName: String
    let engineName: String
    let endpoint: String?
    let message: String
    let technicalDetail: String
}
