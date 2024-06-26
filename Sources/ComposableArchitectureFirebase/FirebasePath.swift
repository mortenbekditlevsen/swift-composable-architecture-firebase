//
//  FirebasePath.swift
//
//
//  Created by Morten Bek Ditlevsen on 23/03/2024.
//

//import FirebaseSharedSwift
//#if canImport(FirebaseFirestore)
//import FirebaseFirestore
//#endif
//#if canImport(FirebaseDatabase)
//import FirebaseDatabase
//#endif

import Foundation

public struct EncodingOptions {
    public init(dateEncodingStrategy: DateEncodingStrategy = .deferredToDate,
                dataEncodingStrategy: DataEncodingStrategy = .deferredToData,
                keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys,
                nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy = .throw,
                userInfo: [CodingUserInfoKey : Any] = [:]) {
        self.dateEncodingStrategy = dateEncodingStrategy
        self.dataEncodingStrategy = dataEncodingStrategy
        self.keyEncodingStrategy = keyEncodingStrategy
        self.nonConformingFloatEncodingStrategy = nonConformingFloatEncodingStrategy
        self.userInfo = userInfo
    }

    /// The strategy to use for encoding `Date` values.
    public enum DateEncodingStrategy {
        /// Defer to `Date` for choosing an encoding. This is the default strategy.
        case deferredToDate
        
        /// Encode the `Date` as a UNIX timestamp (as a JSON number).
        case secondsSince1970
        
        /// Encode the `Date` as UNIX millisecond timestamp (as a JSON number).
        case millisecondsSince1970
        
        /// Encode the `Date` as an ISO-8601-formatted string (in RFC 3339 format).
        @available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
        case iso8601
        
        /// Encode the `Date` as a string formatted by the given formatter.
        case formatted(DateFormatter)
        
        /// Encode the `Date` as a custom value encoded by the given closure.
        ///
        /// If the closure fails to encode a value into the given encoder, the encoder will encode an empty automatic container in its place.
        case custom((Date, Swift.Encoder) throws -> Void)
    }
    
    /// The strategy to use for encoding `Data` values.
    public enum DataEncodingStrategy {
        /// Defer to `Data` for choosing an encoding.
        case deferredToData
        
        /// Encode the `Data` as a Base64-encoded string. This is the default strategy.
        case base64
        
        /// Encode the `Data` as an `NSData` blob.
        case blob
        
        /// Encode the `Data` as a custom value encoded by the given closure.
        ///
        /// If the closure fails to encode a value into the given encoder, the encoder will encode an empty automatic container in its place.
        case custom((Data, Swift.Encoder) throws -> Void)
    }
    
    /// The strategy to use for non-JSON-conforming floating-point values (IEEE 754 infinity and NaN).
    public enum NonConformingFloatEncodingStrategy {
        /// Throw upon encountering non-conforming values. This is the default strategy.
        case `throw`
        
        /// Encode the values using the given representation strings.
        case convertToString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }
    
    /// The strategy to use for automatically changing the value of keys before encoding.
    public enum KeyEncodingStrategy {
        /// Use the keys specified by each type. This is the default strategy.
        case useDefaultKeys
        
        /// Convert from "camelCaseKeys" to "snake_case_keys" before writing a key to JSON payload.
        ///
        /// Capital characters are determined by testing membership in `CharacterSet.uppercaseLetters` and `CharacterSet.lowercaseLetters` (Unicode General Categories Lu and Lt).
        /// The conversion to lower case uses `Locale.system`, also known as the ICU "root" locale. This means the result is consistent regardless of the current user's locale and language preferences.
        ///
        /// Converting from camel case to snake case:
        /// 1. Splits words at the boundary of lower-case to upper-case
        /// 2. Inserts `_` between words
        /// 3. Lowercases the entire string
        /// 4. Preserves starting and ending `_`.
        ///
        /// For example, `oneTwoThree` becomes `one_two_three`. `_oneTwoThree_` becomes `_one_two_three_`.
        ///
        /// - Note: Using a key encoding strategy has a nominal performance cost, as each string key has to be converted.
        case convertToSnakeCase
        
        /// Provide a custom conversion to the key in the encoded JSON from the keys specified by the encoded types.
        /// The full path to the current encoding position is provided for context (in case you need to locate this key within the payload). The returned key is used in place of the last component in the coding path before encoding.
        /// If the result of the conversion is a duplicate key, then only one value will be present in the result.
        case custom((_ codingPath: [CodingKey]) -> CodingKey)
    }

    public let dataEncodingStrategy: DataEncodingStrategy
    public let dateEncodingStrategy: DateEncodingStrategy
    public let keyEncodingStrategy: KeyEncodingStrategy
    public let nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy
    public let userInfo: [CodingUserInfoKey : Any]

    public static var firestoreDefault: Self {
        Self(dataEncodingStrategy: .blob)
    }
    
    public static var rtdbDefault: Self {
        Self()
    }
}

public struct DecodingOptions {
    public init(
        dateDecodingStrategy: DecodingOptions.DateDecodingStrategy = .deferredToDate,
        dataDecodingStrategy: DecodingOptions.DataDecodingStrategy = .base64,
        nonConformingFloatDecodingStrategy: DecodingOptions.NonConformingFloatDecodingStrategy = .throw,
        keyDecodingStrategy: DecodingOptions.KeyDecodingStrategy = .useDefaultKeys,
        userInfo: [CodingUserInfoKey : Any] = [:]
    ) {
        self.dateDecodingStrategy = dateDecodingStrategy
        self.dataDecodingStrategy = dataDecodingStrategy
        self.nonConformingFloatDecodingStrategy = nonConformingFloatDecodingStrategy
        self.keyDecodingStrategy = keyDecodingStrategy
        self.userInfo = userInfo
    }
    
    public enum DateDecodingStrategy {
        /// Defer to `Date` for decoding. This is the default strategy.
        case deferredToDate
        
        /// Decode the `Date` as a UNIX timestamp from a JSON number.
        case secondsSince1970
        
        /// Decode the `Date` as UNIX millisecond timestamp from a JSON number.
        case millisecondsSince1970
        
        /// Decode the `Date` as an ISO-8601-formatted string (in RFC 3339 format).
        @available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
        case iso8601
        
        /// Decode the `Date` as a string parsed by the given formatter.
        case formatted(DateFormatter)
        
        /// Decode the `Date` as a custom value decoded by the given closure.
        case custom((_ decoder: Swift.Decoder) throws -> Date)
    }
    
    /// The strategy to use for decoding `Data` values.
    public enum DataDecodingStrategy {
        /// Defer to `Data` for decoding.
        case deferredToData
        
        /// Decode the `Data` from a Base64-encoded string. This is the default strategy.
        case base64
        
        /// Decode the `Data` as an `NSData` blob.
        case blob
        
        /// Decode the `Data` as a custom value decoded by the given closure.
        case custom((_ decoder: Swift.Decoder) throws -> Data)
    }
    
    /// The strategy to use for non-JSON-conforming floating-point values (IEEE 754 infinity and NaN).
    public enum NonConformingFloatDecodingStrategy {
        /// Throw upon encountering non-conforming values. This is the default strategy.
        case `throw`
        
        /// Decode the values from the given representation strings.
        case convertFromString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }
    
    /// The strategy to use for automatically changing the value of keys before decoding.
    public enum KeyDecodingStrategy {
        /// Use the keys specified by each type. This is the default strategy.
        case useDefaultKeys
        
        /// Convert from "snake_case_keys" to "camelCaseKeys" before attempting to match a key with the one specified by each type.
        ///
        /// The conversion to upper case uses `Locale.system`, also known as the ICU "root" locale. This means the result is consistent regardless of the current user's locale and language preferences.
        ///
        /// Converting from snake case to camel case:
        /// 1. Capitalizes the word starting after each `_`
        /// 2. Removes all `_`
        /// 3. Preserves starting and ending `_` (as these are often used to indicate private variables or other metadata).
        /// For example, `one_two_three` becomes `oneTwoThree`. `_one_two_three_` becomes `_oneTwoThree_`.
        ///
        /// - Note: Using a key decoding strategy has a nominal performance cost, as each string key has to be inspected for the `_` character.
        case convertFromSnakeCase
        
        /// Provide a custom conversion from the key in the encoded JSON to the keys specified by the decoded types.
        /// The full path to the current decoding position is provided for context (in case you need to locate this key within the payload). The returned key is used in place of the last component in the coding path before decoding.
        /// If the result of the conversion is a duplicate key, then only one value will be present in the container for the type to decode from.
        case custom((_ codingPath: [CodingKey]) -> CodingKey)
        
    }
    
    /// The strategy to use in decoding dates. Defaults to `.deferredToDate`.
    public var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate
    
    /// The strategy to use in decoding binary data. Defaults to `.base64`.
    public var dataDecodingStrategy: DataDecodingStrategy = .base64
    
    /// The strategy to use in decoding non-conforming numbers. Defaults to `.throw`.
    public var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .throw
    
    /// The strategy to use for decoding keys. Defaults to `.useDefaultKeys`.
    public var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys
       
    /// Contextual user-provided information for use during decoding.
    public var userInfo: [CodingUserInfoKey : Any] = [:]
    
    public static var firestoreDefault: Self {
        Self(dataDecodingStrategy: .blob)
    }
    
    public static var rtdbDefault: Self {
        Self()
    }
}

public struct FirestoreConfig {
    public init(
        database: String? = nil,
        decodingOptions: DecodingOptions = .firestoreDefault,
        encodingOptions: EncodingOptions = .firestoreDefault
    ) {
        self.database = database
        self.encodingOptions = encodingOptions
        self.decodingOptions = decodingOptions
    }
    
    public var database: String?
    public var encodingOptions: EncodingOptions
    public var decodingOptions: DecodingOptions
}

public struct RTDBConfig {
    public init(
        regionId: String? = nil,
        instanceId: String? = nil,
        decodingOptions: DecodingOptions = .rtdbDefault,
        encodingOptions: EncodingOptions = .rtdbDefault
    ) {
        self.regionId = regionId
        self.instanceId = instanceId
        self.encodingOptions = encodingOptions
        self.decodingOptions = decodingOptions
    }
    
    public var regionId: String?
    public var instanceId: String?
    public var encodingOptions: EncodingOptions
    public var decodingOptions: DecodingOptions
}

public enum PathConfig {
    case firestore(FirestoreConfig)
    case rtdb(RTDBConfig)
    
    public static var firestore: PathConfig { .firestore(.init()) }
    public static var rtdb: PathConfig { .rtdb(.init()) }
}

public enum PathKind {
    case both
    case firestore
    case rtdb
}

public struct FBQuery {
    public var limit: Int?
}

public struct FirebasePath<Element> {
    
    public var config: PathConfig
    
    private var fsComponents: [String]
    private var rtdbComponents: [String]
    public var query: FBQuery?

    public func append<T>(
        _ args: String...,
        config: PathConfig? = nil
    ) -> FirebasePath<T> {
        return FirebasePath<T>(
            fsComponents: fsComponents + args,
            rtdbComponents: rtdbComponents + args,
            config: config ?? self.config,
            query: query
        )
    }
    
    public func append<T>(
        fs fsArgs: String...,
        rtdb rtdbArgs: String...,
        config: PathConfig? = nil
    ) -> FirebasePath<T> {
        return FirebasePath<T>(
            fsComponents: fsComponents + fsArgs,
            rtdbComponents: rtdbComponents + rtdbArgs,
            config: config ?? self.config,
            query: query
        )
    }
        
    private init(
        fsComponents: [String],
        rtdbComponents: [String],
        config: PathConfig,
        query: FBQuery?
    ) {
        self.rtdbComponents = rtdbComponents
        self.fsComponents = fsComponents
        self.config = config
        self.query = query
    }
    
    private var componentsKeyPath: KeyPath<Self, [String]> {
        switch config {
        case .firestore:
            \.fsComponents
        case .rtdb:
            \.rtdbComponents
        }
    }
    
    fileprivate func _limit(_ limit: Int) -> Self {
        var p = self
        var query = p.query ?? FBQuery()
        query.limit = limit
        p.query = query
        return p
    }
    
    public var rendered: String {
        self[keyPath: componentsKeyPath].joined(separator: "/")
    }
}

public typealias CollectionPath<T> = FirebasePath<FirebasePaths.Collection<T>>

public protocol CollectionPathProtocol {
    associatedtype Element
}

public enum FirebasePaths {
    public enum Root {}
    public enum Collection<Element> {}
}

extension FirebasePaths.Collection: CollectionPathProtocol {}

extension FirebasePath where Element == FirebasePaths.Root {
    public init() {
        self.fsComponents = []
        self.rtdbComponents = []
        self.config = .rtdb(.init())
    }
    
    public static var root: Self {
        .init()
    }
}

extension FirebasePath where Element: CollectionPathProtocol {
    public func child(_ key: String) -> FirebasePath<Element.Element> {
        append(key)
    }
    
    public func limit(_ limit: Int) -> Self {
        self._limit(limit)
    }
}

