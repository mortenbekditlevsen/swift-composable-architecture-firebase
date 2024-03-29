//
//  FirebaseStorage.swift
//
//
//  Created by Morten Bek Ditlevsen on 29/03/2024.
//
import Combine
import ComposableArchitecture
import Foundation

/// A type that encapsulates storing to and reading  from Firestore.
public protocol FirebaseStorage: Sendable, AnyObject {
    func async(execute workItem: DispatchWorkItem)
    func asyncAfter(interval: DispatchTimeInterval, execute: DispatchWorkItem)
    func documentListener<T: Decodable>(
        path: FirebasePath<T>,
        handler: @escaping (T) -> Void
    ) -> AnyCancellable
    func collectionListener<T: Decodable>(
        path: CollectionPath<T>,
        handler: @escaping ([(String, T)]) -> Void
    ) -> AnyCancellable
    
    func load<T: Decodable>(from path: FirebasePath<T>) throws -> T
    func save<T: Encodable>(_ value: T, to path: FirebasePath<T>) throws
    func remove<T>(at path: FirebasePath<T>) throws
    func add<T: Encodable>(_ value: T, to path: CollectionPath<T>) throws
}

/// A ``FirebaseStorage`` conformance that emulates a firebase database connections without actually writing anything
/// to the backend.
///
/// This is the version of the ``Dependencies/DependencyValues/defaultFirebaseStorage`` dependency that
/// is used by default when running your app in tests and previews.
public final class EphemeralFirebaseStorage: FirebaseStorage, Sendable {
    public let documentDatabase = LockIsolated<[String: Data]>([:])
    public let collectionDatabase = LockIsolated<[String: [(String, Data)]]>([:])
    private let scheduler: AnySchedulerOf<DispatchQueue>
    private let sourceHandlers = LockIsolated<[String: ((Data) -> Void)]>([:])
    private let collectionHandlers = LockIsolated<[String: (([(String, Data)]) -> Void)]>([:])
    
    public init(scheduler: AnySchedulerOf<DispatchQueue> = .immediate) {
        self.scheduler = scheduler
    }
    
    public func asyncAfter(interval: DispatchTimeInterval, execute workItem: DispatchWorkItem) {
        self.scheduler.schedule(after: self.scheduler.now.advanced(by: .init(interval))) {
            workItem.perform()
        }
    }
    
    public func async(execute workItem: DispatchWorkItem) {
        self.scheduler.schedule(workItem.perform)
    }
    
    public func documentListener<T: Decodable>(
        path: FirebasePath<T>,
        handler: @escaping (T) -> Void
    ) -> AnyCancellable {
        let rendered = path.rendered
        self.sourceHandlers.withValue { $0[rendered] = { data in
            let decoder = JSONDecoder()
            if let t = try? decoder.decode(T.self, from: data) {
                handler(t)
            }
        }
        }
        return AnyCancellable {
            self.sourceHandlers.withValue { $0[rendered] = nil }
        }
    }
    
    public func collectionListener<T: Decodable>(
        path: CollectionPath<T>,
        handler: @escaping ([(String, T)]) -> Void
    ) -> AnyCancellable {
        let rendered = path.rendered
        self.collectionHandlers.withValue { $0[rendered] = { dataArray in
            let decoder = JSONDecoder()
            let values = dataArray.compactMap { (key: String, data: Data) -> (String, T)? in
                guard let value = try? decoder.decode(T.self, from: data) else {
                    return nil
                }
                return (key, value)
            }
            handler(values)
        }
        }
        return AnyCancellable {
            self.collectionHandlers.withValue { $0[rendered] = nil }
        }
    }
    
    struct LoadError: Error {}
    
    public func load<T: Decodable>(from path: FirebasePath<T>) throws -> T {
        let rendered = path.rendered
        let decoder = JSONDecoder()
        guard let data = self.documentDatabase[rendered],
              let value = try? decoder.decode(T.self, from: data)
        else {
            throw LoadError()
        }
        
        return value
    }
    
    public func save<T: Encodable>(_ value: T, to path: FirebasePath<T>) throws {
        let rendered = path.rendered
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        self.documentDatabase.withValue { $0[rendered] = data }
        self.sourceHandlers.value[rendered]?(data)
    }
    
    public func remove<T>(at path: FirebasePath<T>) throws {
        let rendered = path.rendered
        self.documentDatabase.withValue { $0[rendered] = nil }
        self.sourceHandlers.withValue { $0[rendered] = nil }
    }
    
    public func add<T>(_ value: T, to path: CollectionPath<T>) throws where T : Encodable {
        let id = UUID().uuidString
        try save(value, to: path.child(id))
    }
}

public enum FirebaseStorageQueueKey: TestDependencyKey {
    public static var previewValue: any FirebaseStorage {
        EphemeralFirebaseStorage()
    }
    public static var testValue: any FirebaseStorage {
        EphemeralFirebaseStorage()
    }
}

extension DependencyValues {
    public var defaultFirebaseStorage: any FirebaseStorage {
        get { self[FirebaseStorageQueueKey.self] }
        set { self[FirebaseStorageQueueKey.self] = newValue }
    }
}
