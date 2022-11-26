import Foundation

public class StandardAsyncNetworkController {
	private let logger = Logger()

	private let urlSessionBuilder: URLSessionBuilder
	private let urlRequestBuilder: URLRequestBuilder
	private let urlRequestsInterceptors: [any URLRequestInterceptor]

	public init (
		urlSessionBuilder: URLSessionBuilder = .standard(),
		urlRequestBuilder: URLRequestBuilder,
		interceptors: [any URLRequestInterceptor] = []
	) {
		self.urlSessionBuilder = urlSessionBuilder
		self.urlRequestBuilder = urlRequestBuilder
		self.urlRequestsInterceptors = interceptors
	}
}

extension StandardAsyncNetworkController: AsyncNetworkController {
	public func send <RQ: Request> (
		_ request: RQ,
	interceptor: some URLRequestInterceptor = .empty()
	) async throws -> StandardResponse {
		try await send(request, StandardResponse.self, interceptor)
	}

	public func send <RQ: Request, RS: Response> (
		_ request: RQ,
    response: RS.Type,
    interceptor: some URLRequestInterceptor = .empty()
	) async throws -> RS {
		try await send(request, RS.self, interceptor)
	}

	public func send <RQ: Request, RSM: ResponseModel> (
		_ request: RQ,
		responseModel: RSM.Type,
		interceptor: some URLRequestInterceptor = .empty()
	) async throws -> StandardModelResponse<RSM> {
		try await send(request, StandardModelResponse<RSM>.self, interceptor)
	}

	public func send <RQ: Request> (
		_ request: RQ,
		interception: @escaping (_ urlRequest: URLRequest) throws -> URLRequest
	) async throws -> StandardResponse {
		try await send(request, StandardResponse.self, CompactURLRequestInterceptor(interception))
	}

	public func send <RQ: Request, RS: Response> (
		_ request: RQ,
		response: RS.Type,
		interception: @escaping (_ urlRequest: URLRequest) throws -> URLRequest
	) async throws -> RS {
		try await send(request, RS.self, CompactURLRequestInterceptor(interception))
	}

	public func send <RQ: Request, RSM: ResponseModel> (
		_ request: RQ,
		responseModel: RSM.Type,
		interception: @escaping (_ urlRequest: URLRequest) throws -> URLRequest
	) async throws -> StandardModelResponse<RSM> {
		try await send(request, StandardModelResponse<RSM>.self, CompactURLRequestInterceptor(interception))
	}
}

private extension StandardAsyncNetworkController {
	func send <RQ: Request, RS: Response> (_ request: RQ, _ response: RS.Type, _ interceptor: (some URLRequestInterceptor)?) async throws -> RS {
		let requestId = UUID()

		let urlSession: URLSession
		let urlRequest: URLRequest
		do {
			urlSession = try urlSessionBuilder.build(request)

			let buildUrlRequest = try urlRequestBuilder.build(request)
			let interceptors = (interceptor.map { [$0] } ?? []) + urlRequestsInterceptors
			let interceptedUrlRequest = try URLRequestInterceptorChain.create(chainUnits: interceptors)?
				.transform(buildUrlRequest)

			urlRequest = interceptedUrlRequest ?? buildUrlRequest

			logger.log(message: .request(urlSession, urlRequest), requestId: requestId, request: request)
		} catch {
			throw controllerError(
				.init(requestId: requestId, request: request, category: .request(error)),
				requestId,
				request
			)
		}

		let data: Data
		let urlResponse: URLResponse
		do {
			(data, urlResponse) = try await urlSession.data(for: urlRequest)
			logger.log(message: .response(data, urlResponse), requestId: requestId, request: request)
		} catch let urlError as URLError {
			throw controllerError(
				.init(requestId: requestId, request: request, category: .network(.init(urlSession, urlRequest, urlError))),
				requestId,
				request
			)
		} catch {
			throw controllerError(
				.init(requestId: requestId, request: request, category: .general(.other(error))),
				requestId,
				request
			)
		}

		let response: RS
		do {
			response = try .init(data, urlResponse)
		} catch {
			throw controllerError(
				.init(requestId: requestId, request: request, category: .response(error)),
				requestId,
				request
			)
		}

		return response
	}

	func controllerError (_ error: ControllerError, _ requestId: UUID, _ request: Request) -> ControllerError {
		logger.log(message: .error(error), requestId: requestId, request: request)
		return error
	}
}

public extension StandardAsyncNetworkController {
	@discardableResult
	func logging (_ logging: (Logger) -> Void) -> Self {
		logging(logger)
		return self
	}
}

public extension StandardAsyncNetworkController {
	convenience init (
		urlSessionBuilder: URLSessionBuilder = .standard(),
    scheme: @escaping () throws -> String = { "http" },
    basePath: @escaping () throws -> String,
    query: @escaping () throws -> [String: String] = { [:] },
    headers: @escaping () throws -> [String: String] = { [:] },
		interceptors: [any URLRequestInterceptor] = []
	) {
		self.init(
			urlSessionBuilder: urlSessionBuilder,
			urlRequestBuilder: .standard(
				scheme: scheme,
				basePath: basePath,
				query: query,
				headers: headers
			),
			interceptors: interceptors
		)
	}

  convenience init (
    urlSessionBuilder: URLSessionBuilder = .standard(),
    scheme: String = "http",
    basePath: String,
    query: [String: String] = [:],
    headers: [String: String] = [:],
    interceptors: [any URLRequestInterceptor] = []
  ) {
    self.init(
      urlSessionBuilder: urlSessionBuilder,
      urlRequestBuilder: .standard(
        scheme: { scheme },
        basePath: { basePath },
        query: { query },
        headers: { headers }
      ),
      interceptors: interceptors
    )
  }
}
