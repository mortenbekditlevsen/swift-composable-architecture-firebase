//
//  FirebasePath.swift
//
//
//  Created by Morten Bek Ditlevsen on 23/03/2024.
//

import FirebaseSharedSwift
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseDatabase)
import FirebaseDatabase
#endif

public struct FirestoreConfig {
#if canImport(FirebaseFirestore)
    public init(database: String? = nil, getDecoder: @escaping () -> Firestore.Decoder? = { nil }, getEncoder: @escaping () -> Firestore.Encoder? = { nil }) {
        self.database = database
        self.getDecoder = getDecoder
        self.getEncoder = getEncoder
    }
    
    public var database: String?
    public var getDecoder: () -> Firestore.Decoder? = { nil }
    public var getEncoder: () -> Firestore.Encoder? = { nil }
#endif
}

public struct RTDBConfig {
#if canImport(FirebaseDatabase)
    public init(
        regionId: String? = nil,
        instanceId: String? = nil,
        getDecoder: @escaping () -> Database.Decoder? = { nil },
        getEncoder: @escaping () -> Database.Encoder? = { nil }
    ) {
        self.regionId = regionId
        self.instanceId = instanceId
        self.getDecoder = getDecoder
        self.getEncoder = getEncoder
    }
    
    public var regionId: String?
    public var instanceId: String?
    public var getDecoder: () -> Database.Decoder? = { nil }
    public var getEncoder: () -> Database.Encoder? = { nil }
#endif
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

internal struct FBQuery {
    internal var limit: Int?
}

public struct FirebasePath<Element> {
    
    var config: PathConfig
    
    private var fsComponents: [String]
    private var rtdbComponents: [String]
    internal var query: FBQuery?

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

