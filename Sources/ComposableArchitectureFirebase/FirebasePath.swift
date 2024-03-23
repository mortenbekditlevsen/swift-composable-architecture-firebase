//
//  FirebasePath.swift
//
//
//  Created by Morten Bek Ditlevsen on 23/03/2024.
//

public struct FirebasePath<Element>: Equatable, Hashable {
    
    var isFirestorePath: Bool
    
    private var components: [String]
    
    public func append<T>(
        _ args: String...,
        isFirestorePath: Bool? = nil
    ) -> FirebasePath<T> {
        FirebasePath<T>(
            components + args,
            isFirestorePath: isFirestorePath ?? self.isFirestorePath
        )
    }
        
    private init(
        _ components: [String],
        isFirestorePath: Bool
    ) {
        self.components = components
        self.isFirestorePath = isFirestorePath
    }
    
    var rendered: String {
        components.joined(separator: "/")
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

extension FirebasePaths.Collection: CollectionPathProtocol {
}

extension FirebasePath where Element == FirebasePaths.Root {
    public init() {
        self.components = []
        self.isFirestorePath = false
    }
    
    public static var root: Self {
        .init()
    }
}

extension FirebasePath where Element: CollectionPathProtocol {
    public func child(_ key: String) -> FirebasePath<Element.Element> {
        append(key)
    }
}
