//
//  FirebaseStorageLive.swift
//  SharedState
//
//  Created by Morten Bek Ditlevsen on 17/03/2024.
//

import Combine
import ComposableArchitecture
import FirebaseFirestore
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
        path: String,
        handler: @escaping (T) -> Void
    ) -> AnyCancellable {
      let registration = Firestore.firestore().document(path).addSnapshotListener { snap, error in
          if let data = try? snap?.data(as: T.self)  {
              handler(data)
          }
      }
      return AnyCancellable {
          registration.remove()
      }
  }
    
    public func collectionListener<T: Decodable>(
        path: String,
        handler: @escaping ([(String, T)]) -> Void
    ) -> AnyCancellable {
        let registration = Firestore.firestore().collection(path).addSnapshotListener { snap, error in
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
    }


    public func load<T: Decodable>(from path: String) throws -> T {
        var _value: T?
        var _error: Error = MyError.error
        
        // TODO: synchronify this - should be fairly quick to load from cache
        
        Firestore.firestore().document(path).getDocument(source: FirestoreSource.cache) { snap, error in
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
        //      try Data(contentsOf: url)
        if let _value {
            return _value
        }
        throw _error
    }

    public func save<T: Encodable>(_ value: T, to path: String) throws {
        try Firestore.firestore().document(path).setData(from: value) { error in
          guard let error else { return }
          print("Error", error)
      }
  }

}


extension FirebaseStorageQueueKey: DependencyKey {
  public static var liveValue: any FirebaseStorage {
    LiveFirebaseStorage(
      queue: DispatchQueue(label: "co.pointfree.ComposableArchitecture.FirebaseStorage"))
  }
}
