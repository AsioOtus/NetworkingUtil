import Foundation

public protocol ResponseModelDecoder {
	func decode <T: Decodable> (_ type: T.Type, from data: Data) throws -> T
}
