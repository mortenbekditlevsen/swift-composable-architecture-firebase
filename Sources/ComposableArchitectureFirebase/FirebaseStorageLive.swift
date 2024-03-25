//
//  FirebaseStorageLive.swift
//  SharedState
//
//  Created by Morten Bek Ditlevsen on 17/03/2024.
//

import Combine
import ComposableArchitecture
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseDatabase)
import FirebaseDatabase
#endif

import FirebaseSharedSwift
import Foundation

#if canImport(FirebaseFirestore)
extension FirestoreConfig {
    var firestore: Firestore {
        if let database {
            Firestore.firestore(database: database)
        } else {
            Firestore.firestore()
        }
    }
}

extension FBQuery {
    func apply(to ref: Query) -> Query {
        if let limit {
            return ref.limit(to: limit)
        } else {
            return ref
        }
    }
}
#endif

#if canImport(FirebaseDatabase)
extension RTDBConfig {
    var database: Database {
        if let instanceId {
            let url: String
            if let regionId {
                url = "https://\(instanceId).\(regionId).firebasedatabase.app"
            } else {
                url = "https://\(instanceId).firebaseio.com"
            }
            return Database.database(url: url)
        } else {
            return Database.database()
        }
    }
    
}

extension FBQuery {
    func apply(to ref: DatabaseQuery) -> DatabaseQuery {
        if let limit {
            // TODO: Should I worry about conversion to UInt?
            return ref.queryLimited(toFirst: UInt(limit))
        } else {
            return ref
        }
    }
}

#endif

enum MyError: Error {
    case error
}

/// A ``FirebaseStorage`` conformance that interacts directly with Firestore for saving, loading
/// and listening for data changes.
///
/// This is the version of the ``Dependencies/DependencyValues/defaultFirebaseStorage`` dependency that
/// is used by default when running your app in the simulator or on device.
final public class LiveFirebaseStorage: FirebaseStorage {
    private let queue: DispatchQueue
    public init(queue: DispatchQueue) {
        self.queue = queue
    }
    
    public func async(execute workItem: DispatchWorkItem) {
        self.queue.async(execute: workItem)
    }
    
    public func asyncAfter(interval: DispatchTimeInterval, execute workItem: DispatchWorkItem) {
        self.queue.asyncAfter(deadline: .now() + interval, execute: workItem)
    }
    
    public func documentListener<T: Decodable>(
        path: FirebasePath<T>,
        handler: @escaping (T) -> Void
    ) -> AnyCancellable {
        switch path.config {
        case .firestore(let config):
            return documentListenerFirestore(path: path.rendered, 
                                             config: config,
                                             handler: handler)
        case .rtdb(let config):
            return documentListenerRTDB(path: path.rendered,
                                        config: config,
                                        handler: handler)
        }
    }
        
    private func documentListenerFirestore<T: Decodable>(
        path: String,
        config: FirestoreConfig,
        handler: @escaping (T) -> Void
    ) -> AnyCancellable {
#if canImport(FirebaseFirestore)
        let registration = config.firestore
            .document(path)
            .addSnapshotListener { snap, error in
                let decoder = config.getDecoder() ?? .init()
                if let data = try? snap?.data(as: T.self, decoder: decoder)  {
                    handler(data)
                }
            }

        return AnyCancellable {
            registration.remove()
        }
#else
        fatalError("Please link FirebaseFirestore")
#endif
    }
    
    private func documentListenerRTDB<T: Decodable>(
        path: String,
        config: RTDBConfig,
        handler: @escaping (T) -> Void
    ) -> AnyCancellable {
#if canImport(FirebaseDatabase)
        
        let db = config.database
        let ref = db.reference(withPath: path)
        let handle = ref.observe(.value) { snapshot in
            if let data = try? snapshot.data(as: T.self, decoder: config.getDecoder() ?? .init()) {
                handler(data)
            }
        } withCancel: { error in
            // Implement if handler gets error handling
        }
        
        return AnyCancellable {
            ref.removeObserver(withHandle: handle)
        }
#else
        fatalError("Please link FirebaseDatabase")
#endif
    }
    
    public func collectionListener<T: Decodable>(
        path: CollectionPath<T>,
        handler: @escaping ([(String, T)]) -> Void
    ) -> AnyCancellable {
        let query = path.query

        switch path.config {
        case .firestore(let config):
            return collectionListenerFirestore(path: path.rendered, query: query, config: config, handler: handler)
        case .rtdb(let config):
            return collectionListenerRTDB(path: path.rendered, query: query, config: config, handler: handler)
        }
    }
    
    private func collectionListenerFirestore<T: Decodable>(
        path: String,
        query: FBQuery?,
        config: FirestoreConfig,
        handler: @escaping ([(String, T)]) -> Void
    ) -> AnyCancellable {
#if canImport(FirebaseFirestore)
        var ref: Query = config.firestore.collection(path)
        if let query {
            ref = query.apply(to: ref)
        }
        let registration = ref
            .addSnapshotListener { snap, error in
                guard let snap else { return }
                let decoder = config.getDecoder() ?? .init()
                handler(snap.documents.compactMap { documentSnap -> (String, T)? in
                    guard let value = try? documentSnap.data(as: T.self, decoder: decoder) else {
                        return nil
                    }
                    return (documentSnap.documentID, value)
                })
            }
        return AnyCancellable {
            registration.remove()
        }
#else
        fatalError("Please link FirebaseFirestore")
#endif
    }
    
    private func collectionListenerRTDB<T: Decodable>(
        path: String,
        query: FBQuery?,
        config: RTDBConfig,
        handler: @escaping ([(String, T)]) -> Void
    ) -> AnyCancellable {
#if canImport(FirebaseDatabase)
        let db = config.database
        let ref = db.reference(withPath: path)
        let decoder = config.getDecoder() ?? .init()
        let handle = ref.observe(.value) { snapshot, _ in
            // TODO: For now we just unwrap entire value.
            // Consider using child listeners and keep a (very local) cache
            if let data = try? snapshot.data(as: [String: T].self, decoder: decoder) {
                // TODO: Use firebase RTDB key sorting. I have a Swift
                // implementation somewhere
                let sorted = data.sorted(by: { a, b in
                    a.key < b.key
                })
                handler(sorted)
            }
        } withCancel: { error in
            // Implement if handler gets error handling
        }
        
        return AnyCancellable {
            ref.removeObserver(withHandle: handle)
        }
#else
        fatalError("Please link FirebaseDatabase")
#endif
    }
    
    
    public func load<T: Decodable>(from path: FirebasePath<T>) throws -> T {
        switch path.config {
        case .firestore(let config):
            return try loadFirestore(from: path.rendered, config: config)

        case .rtdb(let config):
            return try loadRTDB(from: path.rendered, config: config)
        }
    }
    
    private func loadFirestore<T: Decodable>(
        from path: String,
        config: FirestoreConfig
    ) throws -> T {
#if canImport(FirebaseFirestore)
        var _value: T?
        var _error: Error = MyError.error
        
        // TODO: synchronify this - should be fairly quick to load from cache
        
        config
            .firestore
            .document(path)
            .getDocument(source: FirestoreSource.cache) { snap, error in
            do {
                let decoder = config.getDecoder() ?? .init()
                if let value = try? snap?.data(as: T.self, decoder: decoder) {
                    _value = value
                } else {
                    throw error ?? MyError.error
                }
            } catch {
                _error = error
            }
        }
        if let _value {
            return _value
        }
        throw _error
#else
        fatalError("Please link FirebaseFirestore")
#endif
    }
    
    private func loadRTDB<T: Decodable>(
        from path: String,
        config: RTDBConfig
    ) throws -> T {
#if canImport(FirebaseDatabase)
        // Note: For RTDB you cannot request a value ONLY from cache, so don't attempt to
        // implement this
        throw MyError.error
#else
        fatalError("Please link FirebaseDatabase")
#endif
    }
    
    public func save<T: Encodable>(_ value: T, to path: FirebasePath<T>) throws {
        switch path.config {
        case .firestore(let config):
            try saveFirestore(value, to: path.rendered, config: config)
        case .rtdb(let config):
            try saveRTDB(value, to: path.rendered, config: config)
        }
    }
    
    public func add<T: Encodable>(_ value: T, to path: CollectionPath<T>) throws {
        switch path.config {
        case .firestore(let config):
            try addFirestore(value, to: path.rendered, config: config)
        case .rtdb(let config):
            try addRTDB(value, to: path.rendered, config: config)
        }
    }
    
    private func addFirestore<T: Encodable>(_ value: T, to path: String, config: FirestoreConfig) throws {
#if canImport(FirebaseFirestore)
        let encoder = config.getEncoder() ?? .init()
        try config
            .firestore
            .collection(path)
            .addDocument(from: value, encoder: encoder, completion: { error in
                guard let error else { return }
                print("Error", error)
            })
#else
        fatalError("Please link FirebaseFirestore")
#endif
    }
    
    private func addRTDB<T: Encodable>(_ value: T, to path: String, config: RTDBConfig) throws {
#if canImport(FirebaseDatabase)
        try config
            .database
            .reference(withPath: path)
            .childByAutoId()
            .setValue(from: value, encoder: config.getEncoder() ?? .init()) { error in
                guard let error else { return }
                print("Error", error)
            }
#else
        fatalError("Please link FirebaseDatabase")
#endif
    }


    public func remove<T>(at path: FirebasePath<T>) throws {
        switch path.config {
        case .firestore(let config):
            try removeFirestore(at: path.rendered, config: config)
        case .rtdb(let config):
            try removeRTDB(at: path.rendered, config: config)
        }
    }
    
    private func removeFirestore(at path: String, config: FirestoreConfig) {
#if canImport(FirebaseFirestore)
        try config
            .firestore
            .document(path)
            .delete()
#else
    fatalError("Please link FirebaseFirestore")
#endif
    }
    
    private func removeRTDB(at path: String, config: RTDBConfig) {
#if canImport(FirebaseDatabase)
        try config
            .database
            .reference(withPath: path)
            .removeValue()
#else
        fatalError("Please link FirebaseDatabase")
#endif
    }

    private func saveFirestore<T: Encodable>(_ value: T, to path: String, config: FirestoreConfig) throws {
#if canImport(FirebaseFirestore)
        let encoder = config.getEncoder() ?? .init()
        try config
            .firestore
            .document(path)
            .setData(from: value, encoder: encoder) { error in
                guard let error else { return }
                print("Error", error)
            }
#else
        fatalError("Please link FirebaseFirestore")
#endif
    }
    
    private func saveRTDB<T: Encodable>(_ value: T, to path: String, config: RTDBConfig) throws {
#if canImport(FirebaseDatabase)
        let db = config.database
        let ref = db.reference(withPath: path)
        try ref.setValue(from: value, encoder: config.getEncoder() ?? .init()) { error in
            guard let error else { return }
            print("Error", error)
        }
#else
        fatalError("Please link FirebaseDatabase")
#endif
    }

}

extension FirebaseStorageQueueKey: DependencyKey {
  public static var liveValue: any FirebaseStorage {
    LiveFirebaseStorage(
      queue: DispatchQueue(label: "co.pointfree.ComposableArchitecture.FirebaseStorage"))
  }
}
