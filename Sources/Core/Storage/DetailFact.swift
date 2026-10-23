// SPDX-License-Identifier: MIT
import Foundation

/// One thing the hover card says about a clip below its body. The views turn these into words; they are values so
/// that what a clip type says is tested without a language.
public enum DetailFact: Equatable, Sendable {
    case fromPhone
    case copied(Date)
    case characters(Int)
    case charactersShown(shown: Int, total: Int)
    case language(String)
    case lines(Int)
    case bytes(Int)
    case dimensions(width: Int, height: Int)
    case files(Int)
    case rgb(red: Int, green: Int, blue: Int)
    case secretKind(String)
    case collection(String)
    case pasteCount(Int)
}
