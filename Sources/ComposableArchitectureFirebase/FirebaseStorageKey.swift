import ComposableArchitecture
import IdentifiedCollections
#if canImport(Perception)
import Combine
import Foundation

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WatchKit)
import WatchKit
#endif


/// XXX TODO: Add a protocol that specifies that an `Identifiable` wishes to store it's value in a colleciton by
/// its `ID`. This protocol will require the `ID` to be of `String` type


extension PersistenceKey {
    /// Creates a persistence key that can read and write to a `Codable` value to the file system.
    ///
    /// - Parameter url: The file URL from which to read and write the value.
    /// - Returns: A file persistence key.
    public static func firebase<Value: Codable>(_ path: FirebasePath<Value>) -> Self
    where Self == FirebaseStorageKey<Value> {
        FirebaseStorageKey(path: path)
    }
    
    public static func firebase<Value: Codable>(_ path: CollectionPath<Value>) -> Self
    where Value: Identifiable, Value: Equatable, Self == FirebaseStorageKey<IdentifiedArray<Value.ID, Value>> {
        FirebaseStorageKey(path: path)
    }
    
    public static func firebase<Value>(_ path: CollectionPath<Value>) -> Self
    where Self == FirebaseStorageKey<IdentifiedArray<String, Identified<String, Value>>>, Value: Codable, Value: Equatable {
        FirebaseStorageKey(path: path)
    }
    
    public static func firebase<Value>(_ path: CollectionPath<Value>) -> Self
    where Self == FirebaseStorageKey<[Value]>, Value: Codable, Value: Equatable {
        FirebaseStorageKey(path: path)
    }
}

// TODO: Audit unchecked sendable

/// A type defining a file persistence strategy
///
/// Use ``PersistenceKey/fileStorage(_:)`` to create values of this type.
public final class FirebaseStorageKey<Value: Sendable>: PersistenceKey, @unchecked Sendable
{
    let storage: any FirebaseStorage
    var workItem: DispatchWorkItem?
    
    var _save: (Value) -> Void = { _ in }
    let _load: (Value?) -> Value?
    let _subscribe: (Value?, @escaping (_ newValue: Value?) -> Void) -> Shared<Value>.Subscription

    // Note: Only used for hashing...
    private let renderedPath: String
    
    public init<T: Codable>(path: CollectionPath<T>) where Value == [T] {
        @Dependency(\.defaultFirebaseStorage) var storage
        self.storage = storage
        self.renderedPath = path.rendered

        // Can't save...
        self._save = { _ in }
        self._load = { initialValue in
            initialValue
        }
        self._subscribe = { initialValue, didSet in
            let cancellable = storage.collectionListener(path: path) { (values: [(String, T)]) -> Void in
                didSet(values.map(\.1))
            }
            return Shared.Subscription {
                cancellable.cancel()
            }
        }
    }
    
    public init<T>(path: CollectionPath<T>) where Value == IdentifiedArray<String, Identified<String, T>>, T: Codable, T: Equatable {
        @Dependency(\.defaultFirebaseStorage) var storage
        self.storage = storage
        self.renderedPath = path.rendered
        
        let _value = LockIsolated<IdentifiedArray<String, Identified<String, T>>>([])

        self._save = { newValue in
            let existing = _value.value
            guard newValue != existing else {
                return
            }
            let newIds = newValue.ids
            let existingIds = existing.ids
            let addedIds = newIds.subtracting(existingIds)
            let removedIds = existingIds.subtracting(newIds)
            let commonIds = newIds.intersection(existingIds)
            for id in addedIds {
                print("Adding \(id)")
                if let value = newValue[id: id]?.value {
                    // TODO: Collection errors?
                    try? storage.save(value, to: path.child(id))
                }
            }
            for id in removedIds {
                print("Removing \(id)")
                try? storage.remove(at: path.child(id))
            }
            for id in commonIds {
                guard let new = newValue[id: id]?.value,
                      let old = existing[id: id]?.value else {
                    continue
                }
                if new != old {
                    print("Updating \(id)")
                    try? storage.save(new, to: path.child(id))
                } else {
                    print("Skipping \(id)")
                }
            }
            _value.setValue(newValue)
        }
        self._load = { initialValue in
            initialValue
        }
        self._subscribe = { initialValue, didSet in
            let cancellable = storage.collectionListener(path: path) { (values: [(String, T)]) -> Void in
                let identified = IdentifiedArray(values.map { Identified($0.1, id: $0.0) })
                if identified != _value.value {
                    _value.setValue(identified)
                    didSet(identified)
                }
            }
            return Shared.Subscription {
                cancellable.cancel()
            }
        }
    }
    
    public init<T: Codable>(path: CollectionPath<T>) where T: Identifiable, Value == IdentifiedArray<T.ID, T>, T: Equatable {
        @Dependency(\.defaultFirebaseStorage) var storage
        self.storage = storage
        self.renderedPath = path.rendered
        let _value = LockIsolated<IdentifiedArray<T.ID, T>>([])
        let _map: LockIsolated<[T.ID: String]> = .init([:])

        self._save = { newValue in
            let existing = _value.value
            guard newValue != existing else {
                return
            }
            let newIds = newValue.ids
            let existingIds = existing.ids
            let addedIds = newIds.subtracting(existingIds)
            let removedIds = existingIds.subtracting(newIds)
            let commonIds = newIds.intersection(existingIds)
            for id in addedIds {
                // For added ids, we do not yet have a value in the map.
                // Instead we call the 'add' api
                print("Adding \(id)")
                if let value = newValue[id: id] {
                    // TODO: Collection errors?
                    try? storage.add(value, to: path)
                }
            }
            for id in removedIds {
                guard let mappedId = _map.value[id] else {
                    continue
                }

                print("Removing \(id)")
                try? storage.remove(at: path.child(mappedId))
            }
            for id in commonIds {
                guard let mappedId = _map.value[id] else {
                    continue
                }

                guard let new = newValue[id: id],
                      let old = existing[id: id] else {
                    continue
                }
                if new != old {
                    print("Updating \(id)")
                    try? storage.save(new, to: path.child(mappedId))
                } else {
                    print("Skipping \(id)")
                }
            }
            _value.setValue(newValue)
        }
        self._load = { initialValue in
            initialValue
        }
        self._subscribe = { initialValue, didSet in
            let cancellable = storage.collectionListener(path: path) { (values: [(String, T)]) -> Void in
                let identified = IdentifiedArray(values.map(\.1))
                var map: [T.ID: String] = [:]
                if identified != _value.value {
                    _value.setValue(identified)
                    for (key, value) in values {
                        let id = value.id
                        map[id] = key
                    }
                    _map.withValue { [map] in $0 = map }
                    didSet(identified)
                }
            }
            return Shared.Subscription {
                cancellable.cancel()
            }
        }
    }
    
    public init(path: FirebasePath<Value>) where Value: Codable {
        @Dependency(\.defaultFirebaseStorage) var storage
        self.storage = storage
        self.renderedPath = path.rendered
        let _value = LockIsolated<Value?>(nil)
        
        self._load = { initialValue in
            try? storage.load(from: path) ?? initialValue
        }
        
        self._subscribe = { initialValue, didSet in
            let cancellable = storage.documentListener(path: path) { (value: Value) -> Void in
                didSet(value)
            }
            return Shared.Subscription {
                cancellable.cancel()
            }
        }
        
        self._save = { (value: Value) -> Void in
            _value.setValue(value)
            if self.workItem == nil {
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self, let value = _value.value else { return }
                    try? storage.save(value, to: path)
                    _value.setValue(nil)
                    self.workItem = nil
                }
                self.workItem = workItem
                storage.async(execute: workItem)
            }
        }
    }
    
    
    public func load(initialValue: Value?) -> Value? {
        _load(initialValue)
    }
    
    public func save(_ value: Value) {
        self._save(value)
    }
        
    public func subscribe(
        initialValue: Value?, didSet: @escaping (_ newValue: Value?) -> Void
    ) -> Shared<Value>.Subscription {
        _subscribe(initialValue, didSet)
    }
}

extension FirebaseStorageKey: Hashable {
    public static func == (lhs: FirebaseStorageKey, rhs: FirebaseStorageKey) -> Bool {
        lhs.renderedPath == rhs.renderedPath && lhs.storage === rhs.storage
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.renderedPath)
        hasher.combine(ObjectIdentifier(self.storage))
    }
}

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

/// A ``FileStorage`` conformance that emulates a file system without actually writing anything
/// to disk.
///
/// This is the version of the ``Dependencies/DependencyValues/defaultFileStorage`` dependency that
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

#endif
