import ComposableArchitecture
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

public struct FirebasePath<Element>: Equatable, Hashable {
    
    var isFirestorePath: Bool
    
    private var components: [String]
    
    public func append<T>(
        _ args: [String],
        isFirestorePath: Bool? = nil
    ) -> FirebasePath<T> {
        FirebasePath<T>(
            components + args,
            isFirestorePath: isFirestorePath ?? self.isFirestorePath
        )
    }
    
    private func append<T>(
        _ arg: String,
        isFirestorePath: Bool? = nil
    ) -> FirebasePath<T> {
        FirebasePath<T>(
            components + [arg],
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
        append([key])
    }
}

public struct KeyPair<T: Codable>: Codable {
    public let key: String
    public let value: T
}

extension KeyPair: Equatable where T: Equatable {}

extension KeyPair: Hashable where T: Hashable {}

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
    where Self == FirebaseStorageKey<[Value]> {
        FirebaseStorageKey(path: path)
    }
    
    public static func firebase<Value: Codable>(_ path: CollectionPath<Value>) -> Self
    where Self == FirebaseStorageKey<[(String, Value)]> {
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
  let value: LockIsolated<Value?>
  var workItem: DispatchWorkItem?
  
  var _save: (Value) -> Void = { _ in }
  let _load: (Value?) -> Value?
  
  // Note: Only used for hashing...
  private let renderedPath: String
  
  public init<T: Codable>(path: CollectionPath<T>) where Value == [T] {
      @Dependency(\.defaultFirebaseStorage) var storage
      self.storage = storage
      self.renderedPath = path.rendered
      self.value = LockIsolated<Value?>(nil)
      
      // Can't save...
      self._save = { _ in }
      self._load = { initialValue in
          initialValue
      }
      self._subscribe = { initialValue, didSet in
          let cancellable = storage.collectionListener(path: path.rendered) { (values: [(String, T)]) -> Void in
              didSet(values.map(\.1))
          }
          return Shared.Subscription {
              cancellable.cancel()
          }
      }
  }
  
  /// XXX TODO: With variadic generics we could conform a tuple of codables to being codable.
  public init<T: Codable>(path: CollectionPath<T>) where Value == [(String, T)] {
      @Dependency(\.defaultFirebaseStorage) var storage
      self.storage = storage
      self.renderedPath = path.rendered
      self.value = LockIsolated<Value?>(nil)
      
      // Can't save...
      self._save = { _ in }
      self._load = { initialValue in
          initialValue
      }
      self._subscribe = { initialValue, didSet in
          let cancellable = storage.collectionListener(path: path.rendered) { (values: [(String, T)]) -> Void in
              didSet(values)
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
      self.value = _value
      
      self._load = { initialValue in
          try? storage.load(from: path.rendered) ?? initialValue
      }
      
      self._subscribe = { initialValue, didSet in
          let cancellable = storage.documentListener(path: path.rendered) { (value: Value) -> Void in
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
                  try? storage.save(value, to: path.rendered)
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
  
  let _subscribe: (Value?, @escaping (_ newValue: Value?) -> Void) -> Shared<Value>.Subscription
  
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
      path: String,
      handler: @escaping (T) -> Void
    ) -> AnyCancellable
      func collectionListener<T: Decodable>(
        path: String,
        handler: @escaping ([(String, T)]) -> Void
      ) -> AnyCancellable

      func load<T: Decodable>(from path: String) throws -> T
      func save<T: Encodable>(_ value: T, to path: String) throws
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
    path: String,
    handler: @escaping (T) -> Void
  ) -> AnyCancellable {
      self.sourceHandlers.withValue { $0[path] = { data in
          let decoder = JSONDecoder()
          if let t = try? decoder.decode(T.self, from: data) {
              handler(t)
          }
      }
      }
    return AnyCancellable {
      self.sourceHandlers.withValue { $0[path] = nil }
    }
  }
    
    public func collectionListener<T: Decodable>(
        path: String,
        handler: @escaping ([(String, T)]) -> Void
    ) -> AnyCancellable {
        self.collectionHandlers.withValue { $0[path] = { dataArray in
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
            self.collectionHandlers.withValue { $0[path] = nil }
        }
    }

    struct LoadError: Error {}

    public func load<T: Decodable>(from path: String) throws -> T {
        let decoder = JSONDecoder()
        guard let data = self.documentDatabase[path],
              let value = try? decoder.decode(T.self, from: data)
        else {
            throw LoadError()
        }
        
        return value
    }

    public func save<T: Encodable>(_ value: T, to path: String) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        self.documentDatabase.withValue { $0[path] = data }
        self.sourceHandlers.value[path]?(data)
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

//  @_spi(Internals)
//  public var willResignNotificationName: Notification.Name? {
//    #if os(iOS) || os(tvOS) || os(visionOS)
//      return UIApplication.willResignActiveNotification
//    #elseif os(macOS)
//      return NSApplication.willResignActiveNotification
//    #else
//      if #available(watchOS 7, *) {
//        return WKExtension.applicationWillResignActiveNotification
//      } else {
//        return nil
//      }
//    #endif
//  }

  private var canListenForResignActive: Bool {
      false
//    willResignNotificationName != nil
  }
#endif
