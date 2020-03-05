//
//  CachedValue.swift
//  PlatformKit
//
//  Created by Jack on 19/09/2019.
//  Copyright © 2019 Blockchain Luxembourg S.A. All rights reserved.
//

import Foundation
import RxRelay
import RxSwift

/// This implements an in-memory cache with transparent refreshing/invalidation
/// after `refreshInterval` has elapsed.
public class CachedValue<Value> {
    
    // MARK: Types
    
    /// The fetch method
    private enum FetchMethod {
        
        /// An observable - keeps streaming elements
        case observable(() -> Observable<Value>)
        
        /// A single - streams once and terminates
        case single(() -> Single<Value>)
    }
    
    private enum StreamState {
                
        /// The data has not been calculated yet
        case empty
        
        /// The data should be flushed
        case flush
        
        /// The stream erred at some point and is now invalid
        case invalid
        
        /// The stream is in midst of claculating next element
        case calculating
        
        /// The data should be streamed
        case stream(StreamType)
        
        /// Returns the stream
        var streamType: StreamType? {
            switch self {
            case .stream(let streamType):
                return streamType
            default:
                return nil
            }
        }
    }
    
    /// The type of the stream - only public streams' values are exposed to external subscribers
    private enum StreamType {
        
        /// Stream the value publicly
        case `public`(Value)
        
        /// Stream the value privately
        case `private`(Value)
                
        /// Stream nothing
        case none
        
        var isPublic: Bool {
            if case .public = self {
                return true
            }
            return false
        }
        
        var value: Value? {
            switch self {
            case .private(let value), .public(let value):
                return value
            case .none:
                return nil
            }
        }
    }
    
    /// The caching error
    public enum CacheError: Error, CustomDebugStringConvertible {
        
        /// The fetch has failed for a generic reason
        case fetchFailed
        
        /// The fetch has failed because of an unset fech closure
        case unsetFetchClosure
        
        /// Internal error has occurred
        case internalError
        
        public var debugDescription: String {
            switch self {
            case .fetchFailed:
                return "⚠️ \(String(describing: self)): error - fetch failed"
            case .unsetFetchClosure:
                return "⚠️ \(String(describing: self)): error - `fetch` is not set"
            case .internalError:
                return "⚠️ \(String(describing: self)): error - internal error"
            }
        }
    }
    
    // MARK: - Properties
    
    @available(*, deprecated, message: "Do not use this! It is meant to support legacy code")
    public var legacyValue: Value? {
        return stateRelay.value.streamType?.value
    }
    
    /// Streams a single value and terminates
    public var valueSingle: Single<Value> {
        valueObservable
            .take(1)
            .asSingle()
    }
    
    /// Streams a value upon each refresh.
    public var valueObservable: Observable<Value> {
        stateRelay
            .flatMap(weak: self, fetchPriority: configuration.fetchPriority) { (self, state) -> Observable<StreamType> in
                let fetch = { () -> Observable<StreamType> in
                    guard let fetch = self.fetch else { return .just(.none) }
                    switch fetch {
                    case .observable:
                        return self.fetchAsObservable()
                            .map { _ in StreamType.none }
                    case .single:
                        return self.fetchAsSingle()
                            .asObservable()
                            .map { _ in StreamType.none }
                    }
                }
                
                switch state {
                case .empty:
                    return fetch()
                case .calculating:
                    return .just(.none)
                case .flush:
                    return .just(.none)
                case .invalid:
                    throw CacheError.fetchFailed
                case .stream(.private(let value)):
                    if self.refreshControl.shouldRefresh {
                        return fetch()
                    } else {
                        return .just(.public(value))
                    }
                case .stream(.public), .stream(.none):
                    return .just(.none)
                }
            }
            .catchError { error in
                if case ToolKitError.nullReference = error {
                    return .just(.none)
                }
                throw error
            }
            .filter { $0.isPublic }
            .compactMap { $0.value }
    }
    
    /// Fetches (from remote) and caches the value
    public var fetchValue: Single<Value> {
        fetchAsSingle()
    }
    
    public var fetchValueObservable: Observable<Value> {
        fetchAsObservable()
    }
    
    // MARK: - Private properties
    
    private let stateRelay = BehaviorRelay<StreamState>(value: .empty)
    
    /// The calculation state streams `StreamType` elements to differentiate between publicly streamed elements
    /// which are ready to be distributed to subscribers, and privately streamed elements which are not intended to be distributed
    private var state: Observable<StreamState> {
        stateRelay.asObservable()
    }
            
    private var fetch: FetchMethod?
    private let configuration: CachedValueConfiguration
    private let refreshControl: CachedValueRefreshControl
    
    private let disposeBag = DisposeBag()
    
    // MARK: - Init
    
    public init(configuration: CachedValueConfiguration) {
        self.configuration = configuration
        refreshControl = CachedValueRefreshControl(configuration: configuration)
        refreshControl.action
            .map { action in
                switch action {
                case .fetch:
                    return .empty
                case .flush:
                    return .flush
                }
            }
            .bind(to: stateRelay)
            .disposed(by: disposeBag)
    }
    
    // MARK: - Public methods
    
    /// Performs the fetch action and streams the values.
    /// This method is expected to keep streaming values until a termination / disposal event occurs.
    /// Suitable for complex streams throughout the app.
    public func fetchObservableValue(_ fetch: () -> Observable<Value>) -> Observable<Value> {
        return fetch()
            .do(
                /// On successful fetch make the relay accept a privately distributed value
                onNext: { [weak self] value in
                    guard let self = self else { return }
                    self.refreshControl.update(refreshDate: Date())
                    self.stateRelay.accept(.stream(.private(value)))
                },
                onSubscribe: { [weak stateRelay] in
                    stateRelay?.accept(.calculating)
                }
            )
    }
    
    /// Performs the fetch action and streams a single value.
    /// This method is expected to stream a single value per subscription.
    /// Suitable simple use streams and use cases.
    public func fetchSingleValue(_ fetch: () -> Single<Value>) -> Single<Value> {
        /// Fetch the value
        return fetch()
            .do(
                /// On successful fetch make the relay accept a privately distributed value
                onSuccess: { [weak self] value in
                    guard let self = self else { return }
                    self.refreshControl.update(refreshDate: Date())
                    self.stateRelay.accept(.stream(.private(value)))
                },
                onSubscribe: { [weak stateRelay] in
                    stateRelay?.accept(.calculating)
                }
            )
    }
    
    /// Sets a fetch method that streams an observable
    public func setFetch(_ fetch: @escaping () -> Observable<Value>) {
        self.fetch = .observable(fetch)
    }
    
    /// Sets a fetch method that streams a single
    public func setFetch(_ fetch: @escaping () -> Single<Value>) {
        self.fetch = .single(fetch)
    }
    
    /// Sets a fetch method that streams a single value (doesn't retain the given object)
    public func setFetch<A: AnyObject>(weak object: A, fetch: @escaping (A) -> Single<Value>) {
        self.fetch = .single { [weak object] in
            guard let object = object else {
                return .error(ToolKitError.nullReference(A.self))
            }
            return fetch(object)
        }
    }
    
    /// Sets a fetch method that streams values (doesn't retain the given object)
    public func setFetch<A: AnyObject>(weak object: A, fetch: @escaping (A) -> Observable<Value>) {
        self.fetch = .observable { [weak object] in
            guard let object = object else {
                return .error(ToolKitError.nullReference(A.self))
            }
            return fetch(object)
        }
    }
    
    // MARK: - Private methods
    
    private func fetchAsObservable() -> Observable<Value> {
        guard let fetch = fetch else {
            return .error(CacheError.unsetFetchClosure)
        }
        guard case .observable(let method) = fetch else {
            return .error(CacheError.internalError)
        }
        return fetchObservableValue(method)
    }
    
    private func fetchAsSingle() -> Single<Value> {
        guard let fetch = fetch else {
            return .error(CacheError.unsetFetchClosure)
        }
        guard case .single(let method) = fetch else {
            return .error(CacheError.internalError)
        }
        return fetchSingleValue(method)
    }
}

private extension ObservableType {
    func flatMap<A: AnyObject, R>(weak object: A,
                                  fetchPriority: CachedValueConfiguration.FetchPriority,
                                  selector: @escaping (A, Self.Element) throws -> Observable<R>) -> Observable<R> {
        switch fetchPriority {
        case .fetchAll:
            return flatMap(weak: object, selector: selector)
        case .throttle(milliseconds: let time, scheduler: let scheduler):
            return self.throttle(
                    .milliseconds(time),
                    scheduler: scheduler
                )
                .flatMap(
                    weak: object,
                    selector: selector
                )
        }
    }
}