
# AsyncNinja: a Swift library for concurrency and reactive programming

![Ninja Cat](NinjaCat.png)
![License:MIT](https://img.shields.io/github/license/mashape/apistatus.svg)
[![Build Status](https://travis-ci.org/AsyncNinja/AsyncNinja.svg?branch=master)](https://travis-ci.org/AsyncNinja)
[![CocoaPods](https://img.shields.io/cocoapods/v/AsyncNinja.svg)](https://cocoapods.org/pods/AsyncNinja)

* supports: macOS 10.10+, iOS 8.0+, tvOS 9.0+, watchOS 2.0+, Linux
* `Future`, `Channel`, `DynamicProperty`, `Cache`, `Fallible`, `Executor`, `ExecutionContext`, ...
* neat KVO, target-action, notifications, bindings
* from less to none boilerplate code for threading and memory management
* automated cancellation
* rich collection of transformations (`map`, `filter`, `recover`, `flatMap`, `debounce`, `distinct`, `merge`, `zip`, `sample`, `scan`, ...)
* **[Full Documentation](http://cocoadocs.org/docsets/AsyncNinja/)**

![Tiny Map of Primitives](Documentation/Resources/tiny_map.png)
[see full UML of types](Documentation/Resources/map.svg)

* Related Articles
	* Moving to nice asynchronous Swift code: [GitHub](https://github.com/AsyncNinja/article-moving-to-nice-asynchronous-swift-code/blob/master/ARTICLE.md), [Medium](https://medium.com/@AntonMironov/moving-to-nice-asynchronous-swift-code-7b0cb2eadde1)

### Contents

* [Integration](#integration)
* [Why AsyncNinja?](#why-asyncninja)
* [Using Futures](#using-futures)
* [Using Channels](#using-channels)
* [Reactive Programming](#reactive-programming)

## Integration

* [Swift Package Manager](Documentation/Integration.md#using-swift-package-manager)
* [CocoaPods](Documentation/Integration.md#cocoapods)
* [git submodule](Documentation/Integration.md#using-git-submodule)

## Why AsyncNinja?

Let's assume that we have:

* `Person` is an example of a struct that contains information about the person.
* `MyService` is an example of a class that serves as an entry point to the model. Works in a background.
* `MyViewController` is an example of a class that manages UI-related instances. Works on the main queue.

#### Code on callbacks

```swift
extension MyViewController {
  func present(personWithID identifier: String) {
    myService.fetch(personWithID: identifier) {
      (person, error) in

      /* do not forget to dispatch to the main queue */
      DispatchQueue.main.async {

        /* do not forget the [weak self] */
        [weak self] in
        guard let strongSelf = self
          else { return }

        if let person = person {
          strongSelf.present(person: person)
        } else if let error = error {
          strongSelf.present(error: error)
        } else {
          fatalError("There is neither person nor error. What has happened to this world?")
        }
      }
    }
  }
}

extension MyService {
  func fetch(personWithID: String, callback: @escaping (Person?, Error?) -> Void) {
    /* ... */
  }
}
```

* "do not forget" comment **x2**
* the block will be retained and called even if MyViewController was already deallocated

#### Code with other libraries that provide futures

```swift
extension MyViewController {
  func present(personWithID identifier: String) {
    myService.fetch(personWithID: identifier)

      /* do not forget to dispatch to the main queue */
      .onComplete(executor: .main) {

        /* do not forget the [weak self] */
        [weak self] (completion) in
        if let strongSelf = self {
          completion.onSuccess(strongSelf.present(person:))
          completion.onFailure(strongSelf.present(error:))
        }
      }
  }
}

extension MyService {
  func fetch(personWithID: String) -> Future<Person> {
    /* ... */
  }
}
```

* "do not forget" comment **x2**
* the block will be retained and called even if MyViewController was already deallocated

#### Code with [AsyncNinja](https://github.com/AsyncNinja/AsyncNinja)

```swift
extension MyViewController {
  func present(personWithID identifier: String) {
    myService.fetch(personWithID: identifier)
      .onComplete(context: self) { (self, completion) in
        completion.onSuccess(self.present(person:))
        completion.onFailure(self.present(error:))
      }
  }
}

extension MyService {
  func fetch(personWithID: String) -> Future<Person> {
    /* ... */
  }
}
```

* "do not forget" comment **NONE**
* the block will be retained and called as long as specified context (MyViewController) exists
* [Want to see extended explanation?](https://medium.com/@AntonMironov/moving-to-nice-asynchronous-swift-code-7b0cb2eadde1)

## Using Futures

Let's assume that we have function that finds all prime numbers lesser than n

```swift
func primeNumbers(to n: Int) -> [Int] { /* ... */ }
```

#### Making future

```swift
let futurePrimeNumbers: Future<[Int]> = future { primeNumbers(to: 10_000_000) }
```

#### Applying transformation

```swift
let futureSquaredPrimeNumbers = futurePrimeNumbers
  .map { (primeNumbers) -> [Int] in
    return primeNumbers.map { (number) -> Int
      return number * number
    }
  }
```

#### Synchronously waiting for completion

```swift
if let fallibleNumbers = futurePrimeNumbers.wait(seconds: 1.0) {
  print("Number of prime numbers is \(fallibleNumbers.success?.count)")
} else {
  print("Did not calculate prime numbers yet")
}
```

#### Subscribing for completion

```swift
futurePrimeNumbers.onComplete { (falliblePrimeNumbers) in
  print("Number of prime numbers is \(falliblePrimeNumbers.success?.count)")
}
```

#### Combining futures

```swift
let futureA: Future<A> = /* ... */
let futureB: Future<B> = /* ... */
let futureC: Future<C> = /* ... */
let futureABC: Future<(A, B, C)> = zip(futureA, futureB, futureC)
```

#### Transition from callbacks-based flow to futures-based flow:

```swift
class MyService {
  /* implementation */
  
  func fetchPerson(withID personID: Person.Identifier) -> Future<Person> {
    let promise = Promise<Person>()
    self.fetchPerson(withID: personID, callback: promise.complete)
    return promise
  }
}
```

#### Transition from futures-based flow to callbacks-based flow

```swift
class MyService {
  /* implementation */
  
  func fetchPerson(withID personID: Person.Identifier,
                   callback: @escaping (Fallible<Person>) -> Void) {
    self.fetchPerson(withID: personID)
      .onComplete(callback)
  }
}
```

## Using Channels
Let's assume we have function that returns channel of prime numbers: sends prime numbers as finds them and sends number of found numbers as completion

```swift
func makeChannelOfPrimeNumbers(to n: Int) -> Channel<Int, Int> { /* ... */ }
```

#### Applying transformation

```swift
let channelOfSquaredPrimeNumbers = channelOfPrimeNumbers
  .map { (number) -> Int in
      return number * number
    }
```

#### Synchronously iterating over update values.

```swift
for number in channelOfPrimeNumbers {
  print(number)
}
```

#### Synchronously waiting for completion

```swift
if let fallibleNumberOfPrimes = channelOfPrimeNumbers.wait(seconds: 1.0) {
  print("Number of prime numbers is \(fallibleNumberOfPrimes.success)")
} else {
  print("Did not calculate prime numbers yet")
}
```

#### Synchronously waiting for completion #2

```swift
let (primeNumbers, numberOfPrimeNumbers) = channelOfPrimeNumbers.waitForAll()
```

#### Subscribing for update

```swift
channelOfPrimeNumbers.onUpdate { print("Update: \($0)") }
```

#### Subscribing for completion

```swift
channelOfPrimeNumbers.onComplete { print("Completed: \($0)") }
```

#### Making `Channel`

```swift
func makeChannelOfPrimeNumbers(to n: Int) -> Channel<Int, Int> {
  return channel { (update) -> Int in
    var numberOfPrimeNumbers = 0
    var isPrime = Array(repeating: true, count: n)

    for number in 2..<n where isPrime[number] {
      numberOfPrimeNumbers += 1
      update(number)

      // updating seive
      var seiveNumber = number + number
      while seiveNumber < n {
        isPrime[seiveNumber] = false
        seiveNumber += number
      }
    }

    return numberOfPrimeNumbers
  }
}
```

## Reactive Programming

#### reactive properties
```swift
let searchResults = searchBar.rp.text
  .debounce(interval: 0.3)
  .distinct()
  .flatMap(behavior: .keepLatestTransform) { (query) -> Future<[SearchResult]> in
    return query.isEmpty
      ? .just([])
      : searchGitHub(query: query).recover([])
  }
```

#### bindings

- unbinds automatically
- dispatches to a correct queue automatically
- no  `.observeOn(MainScheduler.instance)` and `.disposed(by: disposeBag)`

```swift
class MyViewController: UIViewController {
  /* ... */
  @IBOutlet weak var myLabel: UILabel!

  override func viewDidLoad() {
    super.viewDidLoad()
    UIDevice.current.rp.orientation
      .map { $0.description }
      .bind(myLabel.rp.text)
  }
  
  /* ... */
}
```

#### contexts usage

- no `[weak self]`
- no `DispatchQueue.main.async { ... }`
- no  `.observeOn(MainScheduler.instance)`

```swift
class MyViewController: NSViewController {
  let service: MyService

  /* ... */
  
  func fetchAndPresentItems(for request: Request) {
    service.perform(request: request)
      .map(context: self, executor: .primary) { (self, response) in
        return self.items(from: response)
      }
      .onSuccess(context: self) { (self, items) in
        self.present(items: items)
      }
  }
  
  func items(from response: Response) throws -> [Items] {
    /* ... extract items from response ... */
  }
  
  func present(items: [Items]) {
    /* ... update UI ... */
  }
}

class MyService {
  func perform(request: Request) -> Future<Response> {
    /* ... */
  }
}
```