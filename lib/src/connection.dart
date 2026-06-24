part of '../keiser_metrics_connection.dart';

class MetricsConnection {
  /// Creates a new instance of [MetricsConnection].
  ///
  /// [restEndpoint] is the REST endpoint for the connection.
  /// [socketEndpoint] is the WebSocket endpoint for the connection.
  /// [shouldEnableWebSocket] is a flag indicating whether to enable WebSocket or not.
  /// [socketTimeout] is the timeout duration for the socket connection.
  /// [concurrentRequestLimit] is the limit for concurrent requests.
  /// [requestRetryLimit] is the limit for request retries.
  /// [shouldEnableErrorLogging] is a flag indicating whether to enable error logging or not.
  MetricsConnection({
    this.restEndpoint = defaultRestEndpoint,
    this.socketEndpoint = defaultSocketEndpoint,
    this.shouldEnableWebSocket = defaultShouldEnableWebSocket,
    this.socketTimeout = defaultSocketConnectionTimeout,
    this.socketMessageTimeout = defaultSocketMessageTimeout,
    this.concurrentRequestLimit = defaultConcurrentRequestLimit,
    this.requestRetryLimit = defaultRequestRetryLimit,
    this.shouldEnableErrorLogging = false,
    this.connectionReconnectDelay,
  }) {
    unawaited(_open());
  }
  // params
  final String restEndpoint;
  final String socketEndpoint;
  final bool shouldEnableWebSocket;
  final int concurrentRequestLimit;
  final int requestRetryLimit;
  final Duration socketTimeout;
  final Duration socketMessageTimeout;
  final Duration? connectionReconnectDelay;
  final bool shouldEnableErrorLogging;

  // internal
  IOWebSocketChannel? _socket;
  Dio? _dio;
  int _lastMessageId = 0;
  int _socketRetryAttempts = 0;
  int _restRetryAttempts = 0;
  bool _shouldRetrySocketConnection = true;
  bool _isRestRetrying = false;
  bool _isDioAvailable = false;
  final List<RequestHandler> _requestQueue = [];
  final Map<int, Completer> _completers = {};
  int _activeRequest = 0;
  bool _isOpen = false;
  String? _accessToken;
  String? _refreshToken;
  Timer? _accessTokenTimer;
  Timer? _inactivityTimer;
  Timer? _stabilityTimer;
  bool _isRefreshTokenInUse = false;
  Completer<void>? _refreshCompleter;
  StreamSubscription? _socketSubscription;

  // state
  AuthenticationState _authenticationStatus = AuthenticationState.unknown;
  ConnectionState _socketConnectionState = ConnectionState.disconnected;
  ServerState _serverStatus = ServerState.offline;
  bool get isSocketConnected =>
      _socketConnectionState == ConnectionState.connected;

  ServerState get serverStatus => _serverStatus;

  // streams
  final StreamController<ConnectionState> _onConnectionChange =
      StreamController<ConnectionState>.broadcast();

  final StreamController<ServerState> _onServerStatusChange =
      StreamController<ServerState>.broadcast();

  final StreamController<AuthenticationState> _onAuthenticationStatusChange =
      StreamController<AuthenticationState>.broadcast();

  final StreamController<MetricsApiError> _onError =
      StreamController<MetricsApiError>.broadcast();

  final StreamController<RefreshTokenChangeEvent> _onRefreshChange =
      StreamController<RefreshTokenChangeEvent>.broadcast();

  final StreamController<ChatRoomMessage> _onChatRoomMessage =
      StreamController<ChatRoomMessage>.broadcast();

  // public getters
  Stream<ConnectionState> get onConnectionStatusChange =>
      _onConnectionChange.stream;

  Stream<ServerState> get onServerStatusChange => _onServerStatusChange.stream;

  Stream<AuthenticationState> get onAuthenticationStatusChange =>
      _onAuthenticationStatusChange.stream;

  Stream<RefreshTokenChangeEvent> get onRefreshTokenChange =>
      _onRefreshChange.stream;

  Stream<MetricsApiError> get onError => _onError.stream;

  Stream<ChatRoomMessage> get onChatRoomMessage => _onChatRoomMessage.stream;

  JWTToken? get decodedAccesstoken =>
      _accessToken != null ? decodeJwt(_accessToken!) : null;

  /// Opens the websocket and REST connections.
  Future<void> _open() async {
    if (_isOpen) {
      return;
    }
    _isOpen = true;
    if (shouldEnableWebSocket) {
      await _openSocket();
    }
    await _openRest();
  }

  /// Closes the websocket and rest connections.
  ///
  /// NOTE: This method does not dispose of the instance. All streams will still
  /// be active. If you want to close & dispose of the instance, use the
  /// `dispose` method instead.
  void close() {
    _shouldRetrySocketConnection = false;
    _closeSocket();
    _closeRest();
    // Tear down lifecycle timers unconditionally. `_setAuthStatus(unknown)`
    // does NOT clear the access-token (keep-alive) timer — only the
    // `unauthenticated` branch does — so cancel it here or it keeps firing
    // requests against a closed connection.
    _accessTokenTimer?.cancel();
    _accessTokenTimer = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    // Reset backoff so a later reopen does not start deep in the delay curve.
    _socketRetryAttempts = 0;
    _restRetryAttempts = 0;
    _setAuthStatus(AuthenticationState.unknown);
    _isOpen = false;
  }

  void _drainSocket() {
    final error = UnexpectedError(message: 'Socket connection closed');
    for (final completer in _completers.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _completers.clear();
  }

  /// Error-completes every in-flight request so awaiters are released instead
  /// of hanging forever once the connection is torn down. Covers both the
  /// socket completers map and the queued REST/socket requests.
  void _drainPendingRequests() {
    final error = UnexpectedError(message: 'Connection closed');
    for (final request in _requestQueue) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(error);
      }
    }
    _requestQueue.clear();
  }

  /// Clears the internal authentication state by removing all tokens
  void clearAuthentication() {
    _setAuthStatus(AuthenticationState.unauthenticated);
  }

  Future<void> _openSocket() async {
    // A retry's delay may elapse after `close()`; never reopen a closed
    // connection.
    if (!_isOpen) {
      return;
    }
    if (isSocketConnected) {
      return;
    }
    await _closeSocket();
    if (shouldEnableErrorLogging) {
      print('Opening socket');
    }
    _shouldRetrySocketConnection = true;
    _socket = IOWebSocketChannel.connect(
      Uri.parse(socketEndpoint),
      connectTimeout: socketTimeout,
    );
    try {
      await _socket!.ready;
      _resetInactivityTimer();
      _setConnectionState(ConnectionState.connected);
      _setServerStatus(ServerState.online);
      // Do NOT reset the backoff on a bare handshake. A server that accepts
      // the WS upgrade then immediately drops would otherwise reset the
      // counter every cycle, pinning reconnects at the 1s floor forever.
      // Only clear the backoff once the connection has proven stable.
      _armStabilityReset();
      _socketSubscription = _socket!.stream.listen(
        _onSocketMessage,
        onError: _onSocketError,
        onDone: _onSocketDone,
      );
    } catch (e) {
      if (shouldEnableErrorLogging) {
        print(e);
      }
      // Detach recovery: a persistently failing handshake must not block
      // `_open()` (which still has to bring REST up) nor chain the reconnect
      // loop onto the caller's await. The retry runs in the background.
      unawaited(_requestServerHealth());
      unawaited(_onSocketDone());
    }
  }

  /// Resets the reconnect backoff only after the socket has stayed up for
  /// [_socketStabilityWindow]. A connection that drops before the window
  /// elapses leaves [_socketRetryAttempts] climbing, so a flapping server is
  /// backed off instead of hammered.
  void _armStabilityReset() {
    _stabilityTimer?.cancel();
    _stabilityTimer = Timer(_socketStabilityWindow, () {
      _socketRetryAttempts = 0;
    });
  }

  Future<void> _closeSocket() async {
    // Tear down state SYNCHRONOUSLY (null the socket, flip disconnected) before
    // any await. The idempotency guard in `_onSocketDone` keys off
    // `_socket == null && disconnected`; if we awaited first, a racing
    // onError/onDone could observe the old non-null socket and spawn a second
    // reconnect loop.
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    final subscription = _socketSubscription;
    final socket = _socket;
    _socketSubscription = null;
    _socket = null;
    _setConnectionState(ConnectionState.disconnected);
    _drainSocket();
    // Fire-and-forget the underlying teardown. A channel whose handshake
    // failed can leave `sink.close()` hanging forever; awaiting it here would
    // stall the entire reconnect loop (callers await this method). Swallow
    // errors — the socket is already gone as far as our state is concerned.
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {}));
    }
    if (socket != null) {
      unawaited(
        socket.sink
            .close(socket_status.normalClosure)
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> _resetInactivityTimer() async {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(seconds: 75), () async {
      if (shouldEnableErrorLogging) {
        print('Socket inactivity timeout');
      }
      await _onSocketDone();
      await _requestServerHealth();
    });
  }

  Future<void> _openRest() async {
    _dio ??= Dio(
      BaseOptions(
        baseUrl: restEndpoint,
        connectTimeout: Duration(milliseconds: 10000),
        sendTimeout: Duration(milliseconds: 15000),
        receiveTimeout: Duration(milliseconds: 45000),
      ),
    );
    _isDioAvailable = true;
    if (isSocketConnected) {
      return;
    }
    await _requestServerHealth();
  }

  void _closeRest() {
    _dio?.close(force: true);
    _isDioAvailable = false;
    _dio = null;
    _setServerStatus(ServerState.offline);
    _drainPendingRequests();
  }

  /// A single REST request failing with a connection-class error must not
  /// declare the whole server offline while the websocket is still healthy:
  /// `_closeRest` flips [ServerState.offline], which `close()`s the socket
  /// and forces consumers into a full reconnect/re-auth cycle. Only treat a
  /// REST failure as server-offline when there is no connected socket left
  /// to vouch for the server.
  void _handleRestConnectionFailure() {
    if (isSocketConnected) {
      return;
    }
    _closeRest();
    // Single-flight: only one reconnect loop may run. Without this guard every
    // concurrent request that hits a connection-class error spawns its own
    // loop, all sharing `_restRetryAttempts` — the counter races up, the
    // backoff tier escalates far faster than wall-clock warrants, and the
    // loops tear down each other's freshly-built Dio. The running loop's own
    // health-check failure re-enters here and is absorbed by the guard.
    unawaited(_retryRestConnection());
  }

  Future<void> _onSocketError(error) async {
    _setConnectionState(ConnectionState.disconnected);
    await _onSocketDone();
    if (shouldEnableErrorLogging) {
      print('Socket Error: $error');
    }
  }

  Future<void> _onSocketDone() async {
    // Idempotent teardown. The stream wires both onError and onDone, and the
    // inactivity timer can race them — without this guard each would spawn its
    // own retry loop, leaving orphaned sockets. Once torn down (socket null +
    // disconnected) a duplicate callback is a no-op.
    if (_socket == null &&
        _socketConnectionState == ConnectionState.disconnected) {
      return;
    }
    await _closeSocket();

    if (_shouldRetrySocketConnection) {
      await _retrySocketConnection();
    }
  }

  Future<void> _retrySocketConnection() async {
    _socketRetryAttempts++;
    final delay =
        connectionReconnectDelay ?? _nextReconnectDelay(_socketRetryAttempts);
    if (shouldEnableErrorLogging) {
      print(
          'Socket Retry Attempt $_socketRetryAttempts, Delay: $delay, Date: ${DateTime.now().toUtc()}');
    }
    await Future.delayed(delay);
    if (shouldEnableErrorLogging) {
      print('Retrying socket connection...');
    }
    await _openSocket();
  }

  Future<void> _retryRestConnection() async {
    // Single self-contained loop. Re-entrant callers (each failing request)
    // are absorbed here so only one backoff chain runs at a time.
    if (_isRestRetrying) {
      return;
    }
    _isRestRetrying = true;
    try {
      // Keep retrying while the connection is open, REST is down, and no
      // socket is vouching for the server. `_openRest`'s health check on
      // failure calls `_handleRestConnectionFailure` -> `_closeRest` (clears
      // `_isDioAvailable`), so the loop condition stays true until a probe
      // succeeds (Dio survives) or the socket reconnects.
      while (_isOpen && !_isDioAvailable && !isSocketConnected) {
        _restRetryAttempts++;
        final delay =
            connectionReconnectDelay ?? _nextReconnectDelay(_restRetryAttempts);
        if (shouldEnableErrorLogging) {
          print(
              'Rest Retry Attempt $_restRetryAttempts, Delay: $delay, Date: ${DateTime.now()}');
        }
        await Future.delayed(delay);
        if (shouldEnableErrorLogging) {
          print('Retrying REST connection...');
        }
        await _openRest();
      }
    } finally {
      _isRestRetrying = false;
    }
  }

  void _setConnectionState(ConnectionState connectionState) {
    if (connectionState == ConnectionState.connected) {
      _setServerStatus(ServerState.online);
    }

    // Only emit on an actual transition. Teardown paths (onError + onDone +
    // inactivity timer) all flip to disconnected; without this guard consumers
    // get a burst of duplicate events.
    if (_socketConnectionState == connectionState) {
      return;
    }
    _socketConnectionState = connectionState;
    // `_closeSocket` is async and may settle after `dispose()` has closed the
    // controllers; guard every emit so a late teardown never throws on a
    // closed stream.
    if (!_onConnectionChange.isClosed) {
      _onConnectionChange.add(_socketConnectionState);
    }
  }

  void _setServerStatus(ServerState status) {
    if (_serverStatus != status) {
      _serverStatus = status;
      if (!_onServerStatusChange.isClosed) {
        _onServerStatusChange.add(status);
      }
      if (_serverStatus == ServerState.online) {
        _restRetryAttempts = 0;
      }
    }
  }

  void _setAuthStatus(AuthenticationState status) {
    if (status == AuthenticationState.unauthenticated) {
      _accessToken = null;
      _refreshToken = null;
      _accessTokenTimer?.cancel();
      _accessTokenTimer = null;
    }
    if (_authenticationStatus != status) {
      _authenticationStatus = status;
      if (!_onAuthenticationStatusChange.isClosed) {
        _onAuthenticationStatusChange.add(status);
      }
    }
  }

  void _onSocketMessage(dynamic data) {
    _resetInactivityTimer();
    try {
      final parsedJson = jsonDecode(data);
      if (parsedJson is String) {
        if (pingRegex.hasMatch(parsedJson)) {
          final pingResults = pingRegex.firstMatch(parsedJson);
          if (pingResults != null && pingResults.group(1) != null) {
            _pong(pingResults.group(1)!);
          }
        } else if (data == 'primus::server::close') {
          _socket?.sink.close(socket_status.goingAway);
        }
      } else if (parsedJson is Map<String, dynamic> &&
          parsedJson.containsKey('context')) {
        if (parsedJson['context'] == 'response') {
          _parseResponse(ResponseMessage.fromMap(parsedJson));
        } else if (parsedJson['context'] == 'user') {
          final chatRoomMessage = ChatRoomMessage.fromMap(parsedJson);
          _onChatRoomMessage.add(chatRoomMessage);
        } else if (!isSocketConnected) {
          _setConnectionState(ConnectionState.connected);
          _setServerStatus(ServerState.online);
          _socketRetryAttempts = 0;
        }
      }
    } catch (error) {
      if (shouldEnableErrorLogging) {
        print('Unparseable response: $error');
      }
    }
  }

  void _pong(String time) {
    _socket!.sink.add('"primus::pong::$time"');
  }

  Future<void> _requestServerHealth() async {
    try {
      await _enqueue(
        path: '/status',
        action: 'core:status',
        method: 'GET',
        shouldRetry: false,
      );
    } catch (error) {
      //
    }
  }

  void _parseResponse(ResponseMessage response) {
    if (response.messageId != null &&
        _completers.containsKey(response.messageId)) {
      final completer = _completers[response.messageId]!;
      if (response.error != null) {
        completer.completeError(response.error!);
      } else {
        completer.complete(response);
      }
      _completers.remove(response.messageId);
    }
  }

  Future<ResponseMessage> _executeRequest(
    String path,
    String action,
    String method,
    bool shouldRetry,
    Map<String, dynamic> queryParameters,
    Map<String, dynamic> socketParameters,
    Map<String, dynamic>? bodyParameters,
  ) async {
    ResponseMessage response;
    try {
      response = await retry(
        () async {
          if (bodyParameters != null) {
            if (!_isDioAvailable) {
              // Body requests can only travel over REST. If the socket is
              // still connected the server is reachable, so lazily rebuild
              // the REST client instead of declaring the server offline.
              if (isSocketConnected) {
                await _openRest();
              } else {
                _setServerStatus(ServerState.offline);
                throw UnexpectedError(message: 'Internet or Server is offline');
              }
            }
            return _actionRest(
              path: path,
              method: method,
              bodyParameters: {
                if (queryParameters['authorization'] != null)
                  'authorization': queryParameters['authorization'],
                ...bodyParameters,
              },
            );
          }

          if (isSocketConnected) {
            return _actionSocket(
                action, {...queryParameters, ...socketParameters});
          }

          if (_isDioAvailable) {
            return _actionRest(
                path: path, method: method, queryParameters: queryParameters);
          }

          _setServerStatus(ServerState.offline);
          throw UnexpectedError(message: 'Internet or Server is offline');
        },
        maxAttempts: shouldRetry ? requestRetryLimit : 0,
        maxDelay: const Duration(seconds: 5),
        retryIf: (e) => e is! MetricsApiError && e is! UnexpectedError,
      );
    } on DioException catch (error) {
      throw UnexpectedError(message: error.message ?? 'Unexpected Error');
    } catch (error) {
      if (shouldEnableErrorLogging) {
        print(
            'Action: $action, Time: ${DateTime.now().toUtc()}, Error: $error');
      }
      if (error is MetricsApiError) {
        rethrow;
      }
      throw UnexpectedError(message: error.toString());
    }
    return response;
  }

  /// Pumps queued requests into execution while there is concurrency budget.
  /// Every request — first-attempt or queued — flows through here so the
  /// [_activeRequest] counter is the single source of truth. Each completion
  /// re-pumps (see [_runQueued]), so the queue can never stall with budget
  /// free and items still waiting.
  void _dequeue() {
    while (
        _requestQueue.isNotEmpty && _activeRequest < concurrentRequestLimit) {
      final request = _requestQueue.removeAt(0);
      _activeRequest++;
      _runQueued(request);
    }
  }

  Future<void> _runQueued(RequestHandler request) async {
    try {
      final response = await _executeRequest(
          request.path,
          request.action,
          request.method,
          request.shouldRetry,
          request.params,
          request.socketParams,
          request.bodyParams);
      request.completer.complete(response);
    } catch (e) {
      request.completer.completeError(e);
    } finally {
      _activeRequest--;
      _dequeue();
    }
  }

  Future<ResponseMessage> _enqueue({
    required String path,
    required String action,
    required String method,
    bool shouldRetry = true,
    Map<String, dynamic> queryParameters = const {},
    Map<String, dynamic> socketParameters = const {},
    Map<String, dynamic>? bodyParameters,
  }) {
    final completer = Completer<ResponseMessage>();
    _requestQueue.add(RequestHandler(
        completer: completer,
        path: path,
        action: action,
        shouldRetry: shouldRetry,
        params: queryParameters,
        socketParams: socketParameters,
        bodyParams: bodyParameters,
        method: method));
    _dequeue();
    return completer.future;
  }

  ResponseMessage _checkIfAuthenticated(ResponseMessage response) {
    // Runs for every response, so a non-map / null payload (lists, status
    // bodies) must not crash. Only inspect maps that actually carry a token.
    final data = response.data;
    if (data is Map<String, dynamic> && data['accessToken'] != null) {
      _updateTokens(AuthenticatedResponse.fromMap(data));
      _setAuthStatus(AuthenticationState.authenticated);
    }

    return response;
  }

  Future<ResponseMessage> _actionSocket(
    String action,
    Map<String, dynamic> params,
  ) {
    _lastMessageId++;
    final messageId = _lastMessageId;
    final args = {
      'messageId': messageId,
      'event': 'action',
      'params': {
        'action': action,
        ...params,
      },
    };
    return _awaitSocketResponse(args, messageId, reconnectOnTimeout: true);
  }

  /// Sends a framed socket request and awaits its correlated response.
  ///
  /// Shared by [_actionSocket] and [sendChatRoomMessage]. When
  /// [reconnectOnTimeout] is true (RPC actions) a timeout tears the socket down
  /// and reconnects, then throws a retryable [TimeoutException] so the caller's
  /// retry loop re-routes the request over REST. When false (fire-and-forget
  /// chat) a timeout simply surfaces as an [UnexpectedError].
  Future<ResponseMessage> _awaitSocketResponse(
    Map<String, dynamic> args,
    int messageId, {
    required bool reconnectOnTimeout,
  }) async {
    final completer = Completer<ResponseMessage>();
    _completers[messageId] = completer;
    try {
      _socket?.sink.add(jsonEncode(args));
      return await completer.future.timeout(socketMessageTimeout);
    } on TimeoutException catch (_) {
      _completers.remove(messageId);
      if (reconnectOnTimeout) {
        // Socket is unresponsive: tear it down + reconnect, and throw a
        // retryable error so `_executeRequest`'s retry falls back to REST.
        unawaited(_onSocketDone());
        throw TimeoutException('Socket message timeout');
      }
      _setConnectionState(ConnectionState.disconnected);
      throw UnexpectedError(message: 'Socket message timeout');
    } catch (error) {
      _completers.remove(messageId);
      if (error is Map<String, dynamic>) {
        throw MetricsApiError.fromMap(error);
      }
      throw UnexpectedError(message: error.toString());
    }
  }

  /// A [MultipartFile] is single-use: once a request body has been sent the
  /// file is finalized and re-sending it throws. The retry wrapper around
  /// [_actionRest] re-invokes this builder per attempt, so hand Dio a clone
  /// and keep the caller's original un-finalized.
  Map<String, dynamic> _cloneMultipartValues(Map<String, dynamic> body) =>
      body.map(
        (key, value) =>
            MapEntry(key, value is MultipartFile ? value.clone() : value),
      );

  Future<ResponseMessage> _actionRest({
    required String path,
    required dynamic method,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? bodyParameters,
  }) async {
    try {
      final response = await _dio!.request<Object>(
        path,
        options: Options(method: method),
        queryParameters: queryParameters != null && queryParameters.isNotEmpty
            ? queryParameters
            : null,
        data: bodyParameters != null && bodyParameters.isNotEmpty
            ? FormData.fromMap(_cloneMultipartValues(bodyParameters))
            : null,
      );
      _setServerStatus(ServerState.online);
      return ResponseMessage(data: response.data);
    } on DioException catch (e) {
      String message = '';

      if (e.message != null) {
        message = e.message!;
      } else if (e.error is HttpException) {
        final error = e.error as HttpException;
        message = error.message;
      }

      message = message.toLowerCase();
      if (shouldEnableErrorLogging) {
        print(message);
      }
      if (e.type == DioExceptionType.connectionTimeout) {
        _handleRestConnectionFailure();
      } else if (e.type == DioExceptionType.connectionError) {
        _handleRestConnectionFailure();
      } else if (e.type == DioExceptionType.unknown) {
        if (message.contains('connection failed') ||
            message.contains('connection closed') ||
            message.contains('connection refused')) {
          _handleRestConnectionFailure();
        }
      } else if (e.type == DioExceptionType.badResponse ||
          (e.response != null && e.response!.data is Map<String, dynamic>)) {
        if (e.response != null &&
            e.response!.data is Map<String, dynamic> &&
            e.response!.data.containsKey('error')) {
          throw MetricsApiError.fromMap(e.response!.data['error']);
        }
        if (e.message != null &&
            e.message!.contains('Http status error [503]')) {
          _handleRestConnectionFailure();
        }
      }
      rethrow;
    }
  }

  void _updateTokens(AuthenticatedResponse authenticatedResponse) {
    _accessToken = authenticatedResponse.accessToken;

    if (_accessTokenTimer != null) {
      _accessTokenTimer!.cancel();
    }
    if (decodedAccesstoken!.exp != null) {
      final tokenTTL = decodedAccesstoken!.exp! * 1000 -
          DateTime.now().millisecondsSinceEpoch -
          jwtTTLLimit;
      _accessTokenTimer = Timer(Duration(milliseconds: tokenTTL), _keepAlive);
    }

    if (authenticatedResponse.refreshToken != null) {
      _refreshToken = authenticatedResponse.refreshToken;
      _onRefreshChange
          .add(RefreshTokenChangeEvent(refreshToken: _refreshToken!));
    }
  }

  Future<void> _keepAlive({
    bool shouldThrow = false,
  }) async {
    try {
      await action(
        path: '/auth/keep-alive',
        action: 'auth:keepAlive',
        method: 'POST',
      );
    } catch (_) {
      if (shouldThrow) {
        rethrow;
      }
    }
  }

  /// Creates an authenticated session. This method must be called before
  /// making any requests to authenticated routes.
  ///
  /// You can obtain a refresh token by signing in via our website.
  Future<void> initializeAuthenticatedSession({
    required String token,
  }) async {
    _updateTokens(AuthenticatedResponse(accessToken: token));
    await _keepAlive(shouldThrow: true);
  }

  /// Initializes an authenticated machine session directly from the provided token.
  ///
  /// Unlike [initializeAuthenticatedSession], this method:
  /// - Does not validate the token with the server via keep-alive
  /// - Does not emit an [AuthenticationState.authenticated] event
  ///
  /// Use this for machine initialization tokens that are
  /// device-bound and do not require the standard user session flow.
  void initializeAuthenticatedMachineSessionToken({
    required String token,
  }) {
    _updateTokens(AuthenticatedResponse(accessToken: token));
  }

  /// This method makes a request to a desired route.
  Future<ResponseMessage> action({
    required String path,
    required String action,
    required String method,
    Map<String, dynamic> queryParameters = const {},
    Map<String, dynamic> socketParameters = const {},
    Map<String, dynamic>? bodyParameters,
  }) async {
    ResponseMessage response;
    try {
      response = await _enqueue(
        action: action,
        queryParameters: {
          'authorization': _accessToken,
          ...queryParameters,
        },
        socketParameters: socketParameters,
        bodyParameters: bodyParameters,
        method: method,
        path: path,
      );
    } on MetricsApiError catch (error) {
      if (error.code == 616) {
        // 616 -> invalid token
        if (_refreshToken == null) {
          // invalid token and no refresh token
          _setAuthStatus(AuthenticationState.unauthenticated);
          rethrow;
        }
        if (_isRefreshTokenInUse) {
          // A refresh is already in flight. Spending the refresh token a
          // second time concurrently risks blacklisting it, so wait for the
          // in-flight refresh and then retry this request with the freshly
          // issued access token.
          try {
            await _refreshCompleter?.future;
          } catch (_) {
            // Refresh failed; the original 616 stands.
            rethrow;
          }
          response = await _enqueue(
            action: action,
            queryParameters: {
              'authorization': _accessToken,
              ...queryParameters,
            },
            socketParameters: socketParameters,
            bodyParameters: bodyParameters,
            method: method,
            path: path,
          );
        } else {
          _isRefreshTokenInUse = true;
          final refreshCompleter = Completer<void>();
          _refreshCompleter = refreshCompleter;
          // The refresher reports failure to itself via `rethrow`; this guard
          // stops the shared future from surfacing an unhandled async error
          // when no concurrent request happens to be awaiting it.
          refreshCompleter.future.ignore();
          try {
            response = await _enqueue(
              action: action,
              queryParameters: {
                'authorization': _refreshToken,
                ...queryParameters,
              },
              socketParameters: socketParameters,
              bodyParameters: bodyParameters,
              method: method,
              path: path,
            );
            // Publish the new access token before releasing waiters so their
            // retry picks it up.
            _checkIfAuthenticated(response);
            refreshCompleter.complete();
          } on MetricsApiError catch (error) {
            if (error.code == 615 || error.code == 616) {
              // 615 -> blacklisted token
              // 616 -> invalid token
              _setAuthStatus(AuthenticationState.unauthenticated);
            }
            refreshCompleter.completeError(error);
            rethrow;
          } catch (e) {
            refreshCompleter.completeError(e);
            rethrow;
          } finally {
            _isRefreshTokenInUse = false;
            _refreshCompleter = null;
          }
        }
      } else if (error.code == 615 ||
          (error.code == 613 && _accessToken == null)) {
        // 613 -> UnauthorizedToken
        // 615 -> blacklisted token
        _setAuthStatus(AuthenticationState.unauthenticated);
        rethrow;
      } else {
        rethrow;
      }
    } catch (_) {
      rethrow;
    }
    return _checkIfAuthenticated(response);
  }

  /// Send a websocket message directly to a server chatroom
  Future<ResponseMessage> sendChatRoomMessage({
    required String room,
    required Map<String, dynamic> params,
  }) {
    _lastMessageId++;
    final messageId = _lastMessageId;
    final args = {
      'messageId': messageId,
      'event': 'say',
      'room': room,
      'message': {
        'authorization': _accessToken,
        ...params,
      },
    };
    return _awaitSocketResponse(args, messageId, reconnectOnTimeout: false);
  }

  /// Closes and disposes everything within the connection class.
  Future<void> dispose() async {
    close();
    await _onConnectionChange.close();
    await _onServerStatusChange.close();
    await _onAuthenticationStatusChange.close();
    await _onError.close();
    await _onRefreshChange.close();
    await _onChatRoomMessage.close();
  }
}
