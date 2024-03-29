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
                    // Hmm, I don't know if this is a good idea...
                    // But it's a bit annoying that in the situation
                    // where you don't have `Identifiable` entities
                    // (since you likely don't care about them)
                    // you have to provide ids when appending to the collection.
                    // I'll experiment with using the empty string as a magic value...
                    if id == "" {
                        try? storage.add(value, to: path)
                    } else {
                        try? storage.save(value, to: path.child(id))
                    }
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


#endif
