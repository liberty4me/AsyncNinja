//
//  Copyright (c) 2016 Anton Mironov
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom
//  the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
//  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

import Dispatch

public class Channel<T> : Periodical {
  public typealias PeriodicalValue = T
  public typealias Value = PeriodicalValue
  public typealias Handler = ChannelHandler<Value>
  public typealias PeriodicalHandler = Handler

  let releasePool = ReleasePool()

  init() { }

  public func makePeriodicalHandler(executor: Executor,
                                    block: @escaping (PeriodicalValue) -> Void) -> Handler? {
    /* abstract */
    fatalError()
  }
}

public extension Channel {
  func map<T>(executor: Executor = .primary,
           transform: @escaping (Value) -> T) -> Channel<T> {
    return self.mapPeriodic(executor: executor, transform: transform)
  }
  
  func onValue<U: ExecutionContext>(context: U, executor: Executor? = nil,
               block: @escaping (U, Value) -> Void) {
    self.onPeriodic(context: context, block: block)
  }

  func flatMap<T>(executor: Executor = .primary,
               transform: @escaping (Value) -> T?) -> Channel<T> {
    return self.flatMapPeriodic(executor: executor, transform: transform)
  }

  func flatMap<S: Sequence>(executor: Executor = .primary,
               transform: @escaping (Value) -> S) -> Channel<S.Iterator.Element> {
    return self.flatMapPeriodic(executor: executor, transform: transform)
  }

  func filter(executor: Executor = .immediate,
              predicate: @escaping (Value) -> Bool) -> Channel<Value> {
    return self.filterPeriodical(executor: executor, predicate: predicate)
  }

  func delayed(timeout: Double) -> Channel<PeriodicalValue> {
    return self.delayedPeriodical(timeout: timeout)
  }
}

extension Channel {
  func makeFiniteProducer<T>(executor: Executor, cancellationToken: CancellationToken?,
                                   onPeriodic: @escaping (PeriodicalValue, FiniteProducer<T, Error>) throws -> Void) -> FiniteProducer<T, Error> {
    let producer = FiniteProducer<T, Error>()
    let handler = self.makePeriodicalHandler(executor: executor) { [weak producer] (periodicalValue) in
      guard let producer = producer else { return }
      do { try onPeriodic(periodicalValue, producer) }
      catch { producer.complete(with: error) }
    }

    if let handler = handler {
      producer.releasePool.insert(handler)
    }

    if let cancellationToken = cancellationToken {
      cancellationToken.notifyCancellation { [weak producer] in
        producer?.complete(with: ConcurrencyError.cancelled)
      }
    }

    return producer
  }

  func makeFiniteProducer<T, U: ExecutionContext>(context: U, executor: Executor?, cancellationToken: CancellationToken?,
                                   onPeriodic: @escaping (U, PeriodicalValue, FiniteProducer<T, Error>) throws -> Void) -> FiniteProducer<T, Error> {
    let producer: FiniteProducer<T, Error> = self.makeFiniteProducer(executor: executor ?? context.executor, cancellationToken: cancellationToken) {
      [weak context] (periodicalValue, producer) in
      guard let context = context else { return }
      try onPeriodic(context, periodicalValue, producer)
    }
    context.notifyDeinit { [weak producer] (periodicalValue) in
      guard let producer = producer else { return }
      producer.complete(with: ConcurrencyError.contextDeallocated)
    }
    return producer
  }

  func makeFiniteChannel<T>(executor: Executor, cancellationToken: CancellationToken?,
                         onPeriodic: @escaping (PeriodicalValue, (T) throws -> Void) throws -> Void) -> FiniteChannel<T, Error> {
    return self.makeFiniteProducer(executor: executor, cancellationToken: cancellationToken) { (periodicalValue: PeriodicalValue, producer: FiniteProducer<T, Error>) -> Void in
      try onPeriodic(periodicalValue) { producer.send($0) }
    }
  }

  func makeFiniteChannel<T, U: ExecutionContext>(context: U, executor: Executor?, cancellationToken: CancellationToken?,
                                  onPeriodic: @escaping (U, PeriodicalValue, (T) throws -> Void) throws -> Void) -> FiniteChannel<T, Error> {
    return self.makeFiniteProducer(context: context, executor: executor, cancellationToken: cancellationToken) {
      (context, periodicalValue, producer) -> Void in
      try onPeriodic(context, periodicalValue) { producer.send($0) }
    }
  }
}

public extension Channel {
  func map<T, U: ExecutionContext>(context: U, executor: Executor? = nil, cancellationToken: CancellationToken? = nil,
                   transform: @escaping (U, Value) throws -> T) -> FiniteChannel<T, Error> {
    return self.makeFiniteChannel(context: context, executor: executor, cancellationToken: cancellationToken) {
      (context: U, periodicalValue: Channel.PeriodicalValue, send: (T) throws -> Void) in
      let transformedValue = try transform(context, periodicalValue)
      try send(transformedValue)
    }
  }

  func flatMap<T, U: ExecutionContext>(context: U, executor: Executor? = nil, cancellationToken: CancellationToken? = nil,
               transform: @escaping (U, Value) throws -> T?) -> FiniteChannel<T, Error> {
    return self.makeFiniteChannel(context: context, executor: executor, cancellationToken: cancellationToken) {
      (context: U, periodicalValue: Channel.PeriodicalValue, send: (T) throws -> Void) in
      if let transformedValue = try transform(context, periodicalValue) {
        try send(transformedValue)
      }
    }
  }

  func flatMap<S: Sequence, U: ExecutionContext>(context: U, executor: Executor? = nil, cancellationToken: CancellationToken? = nil,
               transform: @escaping (U, Value) throws -> S) -> FiniteChannel<S.Iterator.Element, Error> {
    return self.makeFiniteChannel(context: context, executor: executor, cancellationToken: cancellationToken) {
      (context: U, periodicalValue: Channel.PeriodicalValue, send: (S.Iterator.Element) throws -> Void) in
      for transformedValue in try transform(context, periodicalValue) {
        try send(transformedValue)
      }
    }
  }
}

/// **internal use only**
final public class ChannelHandler<T> {
  public typealias PeriodicalValue = T

  let executor: Executor
  let block: (PeriodicalValue) -> Void

  public init(executor: Executor,
              block: @escaping (PeriodicalValue) -> Void) {
    self.executor = executor
    self.block = block
  }

  func handle(_ value: PeriodicalValue) {
    let block = self.block
    self.executor.execute { block(value) }
  }
}
