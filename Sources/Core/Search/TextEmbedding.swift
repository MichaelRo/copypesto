// SPDX-License-Identifier: MIT
import Foundation

/// Turns clip text into the vector that semantic search compares; injectable so a test needs no language model.
public protocol TextEmbedding: Sendable {
    func embed(text: String) async -> Data?
}

public struct NoEmbedding: TextEmbedding {
    public init() {}

    public func embed(text _: String) async -> Data? {
        nil
    }
}

extension SemanticIndexer: TextEmbedding {}
