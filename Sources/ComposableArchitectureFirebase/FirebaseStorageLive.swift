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

enum MyError: Error {
    case error
}

/// A ``FileStorage`` conformance that interacts directly with the file system for saving, loading
/// and listening for file changes.
///
/// This is the version of the ``Dependencies/DependencyValues/defaultFileStorage`` dependency that
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
        if path.isFirestorePath {
            return documentListenerFirestore(path: path, handler: handler)
        } else {
            return documentListenerRTDB(path: path, handler: handler)
        }
    }
    
    private func documentListenerFirestore<T: Decodable>(
        path: FirebasePath<T>,
        handler: @escaping (T) -> Void
    ) -> AnyCancellable {
#if canImport(FirebaseFirestore)
        
        let registration = Firestore.firestore().document(path.rendered).addSnapshotListener { snap, error in
            if let data = try? snap?.data(as: T.self)  {
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
        path: FirebasePath<T>,
        handler: @escaping (T) -> Void
    ) -> AnyCancellable {
#if canImport(FirebaseDatabase)
        
        let db = Database.database()
        let ref = db.reference(withPath: path.rendered)
        let handle = ref.observe(.value) { snapshot in
            if let data = try? snapshot.data(as: T.self) {
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
        if path.isFirestorePath {
            return collectionListenerFirestore(path: path, handler: handler)
        } else {
            return collectionListenerRTDB(path: path, handler: handler)
        }
    }
    
    private func collectionListenerFirestore<T: Decodable>(
        path: CollectionPath<T>,
        handler: @escaping ([(String, T)]) -> Void
    ) -> AnyCancellable {
#if canImport(FirebaseFirestore)
        let registration = Firestore.firestore().collection(path.rendered).addSnapshotListener { snap, error in
            guard let snap else { return }
            handler(snap.documents.compactMap { documentSnap -> (String, T)? in
                guard let value = try? documentSnap.data(as: T.self) else {
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
        path: CollectionPath<T>,
        handler: @escaping ([(String, T)]) -> Void
    ) -> AnyCancellable {
#if canImport(FirebaseDatabase)
        let db = Database.database()
        let ref = db.reference(withPath: path.rendered)
        let handle = ref.observe(.value) { snapshot, _ in
            // TODO: For now we just unwrap entire value.
            // Consider using child listeners and keep a (very local) cache
            if let data = try? snapshot.data(as: [String: T].self) {
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
        if path.isFirestorePath {
            return try loadFirestore(from: path)
        } else {
            return try loadRTDB(from: path)
        }
    }
    
    private func loadFirestore<T: Decodable>(from path: FirebasePath<T>) throws -> T {
#if canImport(FirebaseFirestore)
        var _value: T?
        var _error: Error = MyError.error
        
        // TODO: synchronify this - should be fairly quick to load from cache
        
        Firestore.firestore().document(path.rendered).getDocument(source: FirestoreSource.cache) { snap, error in
            do {
                if let value = try? snap?.data(as: T.self) {
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
    
    private func loadRTDB<T: Decodable>(from path: FirebasePath<T>) throws -> T {
#if canImport(FirebaseDatabase)
        // Note: For RTDB you cannot request a value ONLY from cache, so don't attempt to
        // implement this
        throw MyError.error
#else
        fatalError("Please link FirebaseDatabase")
#endif
    }
    
    public func save<T: Encodable>(_ value: T, to path: FirebasePath<T>) throws {
        if path.isFirestorePath {
            try saveFirestore(value, to: path)
        } else {
            try saveRTDB(value, to: path)
        }
    }
    
    private func saveFirestore<T: Encodable>(_ value: T, to path: FirebasePath<T>) throws {
#if canImport(FirebaseFirestore)
        try Firestore.firestore().document(path.rendered).setData(from: value) { error in
            guard let error else { return }
            print("Error", error)
        }
#else
        fatalError("Please link FirebaseFirestore")
#endif
    }
    
    private func saveRTDB<T: Encodable>(_ value: T, to path: FirebasePath<T>) throws {
#if canImport(FirebaseDatabase)
        let db = Database.database()
        let ref = db.reference(withPath: path.rendered)
        try ref.setValue(from: value) { error in
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
