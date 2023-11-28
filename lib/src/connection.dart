part of keiser_metrics_connection;

class MetricsConnection {
  MetricsConnection({
    this.restEndpoint = defaultRestEndpoint,
    this.socketEndpoint = defaultSocketEndpoint,
    this.shouldEnableWebSocket = defaultShouldEnableWebSocket,
    this.socketTimeout = defaultSocketTimeout,
    this.concurrentRequestLimit = defaultConcurrentRequestLimit,
    this.requestRetryLimit = defaultRequestRetryLimit,
    this.shouldEnableErrorLogging = false,
  }) {
    open();
  }

  // params
  final String restEndpoint;
  final String socketEndpoint;
  final bool shouldEnableWebSocket;
  final int concurrentRequestLimit;
  final int requestRetryLimit;
  final Duration socketTimeout;
  final bool shouldEnableErrorLogging;

  // internal
  WebSocketChannel? _socket;
  Dio? _dio;
  int _lastMessageId = 0;
  int _socketRetryAttempts = 0;
  bool _shouldRetrySocketConnection = true;
  bool _isDioAvailable = false;
  final List<RequestHandler> _requestQueue = [];
  final Map<int, Completer> _completers = {};
  int _activeRequest = 0;
  bool _isOpen = false;
  String? _accessToken;
  String? _refreshToken;
  Timer? _accessTokenTimer;
  bool _isRefreshTokenInUse = false;
  StreamSubscription? _socketSubscription;

  // state
  AuthenticationState _authenticationStatus = AuthenticationState.unknown;
  ConnectionState _socketConnectionState = ConnectionState.disconnected;
  ServerState _serverStatus = ServerState.offline;
  bool get isSocketConnected =>
      _socketConnectionState == ConnectionState.connected;

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

  // public getters
  Stream<ConnectionState> get onConnectionStatusChange =>
      _onConnectionChange.stream;

  Stream<ServerState> get onServerStatusChange => _onServerStatusChange.stream;

  Stream<AuthenticationState> get onAuthenticationStatusChanged =>
      _onAuthenticationStatusChange.stream;

  Stream<MetricsApiError> get onError => _onError.stream;

  SessionToken? get decodedAccesstoken =>
      _accessToken != null ? decodeJwt(_accessToken!) : null;

  Stream<RefreshTokenChangeEvent> get onRefreshToken => _onRefreshChange.stream;

  void open() {
    if (_isOpen) {
      return;
    }
    _isOpen = true;
    _openRest();

    if (shouldEnableWebSocket) {
      _openSocket();
    }
  }

  void close() {
    _isOpen = false;
    _shouldRetrySocketConnection = false;
    _closeSocket();
    _closeRest();
  }

  void _openSocket() async {
    if (isSocketConnected) {
      _closeSocket();
    }
    _shouldRetrySocketConnection = true;
    _socket = WebSocketChannel.connect(
      Uri.parse(socketEndpoint),
    );
    try {
      await _socket!.ready.timeout(socketTimeout);
      _socketSubscription = _socket!.stream.listen(
        _onSocketMessage,
        onError: _onSocketError,
        onDone: _onSocketDone,
      );
    } catch (e) {
      if (shouldEnableErrorLogging) {
        print(e);
      }
      _requestServerHealth();
      _onSocketDone();
    }
  }

  void _closeSocket() {
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _socket?.sink.close(socket_status.normalClosure);
    _socket = null;
    _setConnectionState(ConnectionState.disconnected);
  }

  void _openRest() {
    _dio ??= Dio(
      BaseOptions(
        baseUrl: restEndpoint,
        connectTimeout: 5000,
        receiveTimeout: 3000,
      ),
    );
    _isDioAvailable = true;
  }

  void _closeRest() {
    _dio?.close();
    _isDioAvailable = false;
  }

  void _onSocketError(error) {
    _setConnectionState(ConnectionState.disconnected);
    if (shouldEnableErrorLogging) {
      print('Socket Error: $error');
    }
  }

  void _onSocketDone() {
    _closeSocket();

    if (_shouldRetrySocketConnection) {
      _retrySocketConnection();
    }
  }

  void _retrySocketConnection() async {
    int retryTimeout = 0;
    if (_socketRetryAttempts > 3 && _socketRetryAttempts < 6) {
      retryTimeout = 2000; // 6 seconds
    } else if (_socketRetryAttempts >= 6 && _socketRetryAttempts < 20) {
      retryTimeout = 30000; // 7 minutes
    } else if (_socketRetryAttempts >= 20 && _socketRetryAttempts < 28) {
      retryTimeout = 60000; // 8 minutes
    } else if (_socketRetryAttempts >= 28) {
      return;
    }
    _socketRetryAttempts++;
    await Future.delayed(Duration(milliseconds: retryTimeout));
    _openSocket();
  }

  void _setConnectionState(ConnectionState connectionState) {
    if (connectionState == ConnectionState.connected) {
      _setServerStatus(ServerState.online);
    }

    _socketConnectionState = connectionState;
    _onConnectionChange.add(_socketConnectionState);
  }

  void _setServerStatus(ServerState status) {
    if (_serverStatus != status) {
      _serverStatus = status;
      _onServerStatusChange.add(status);
    }
  }

  void _setAuthStatus(AuthenticationState status) {
    if (_authenticationStatus != status) {
      _authenticationStatus = status;
      _onAuthenticationStatusChange.add(status);
    }
  }

  void _onSocketMessage(dynamic data) {
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

  void _requestServerHealth() async {
    try {
      // TODO - change this to core:status when/if apollo server is updated
      await enqueue(
        path: '/status',
        action: 'status',
        method: r'GET',
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

  Future<ResponseMessage> executeRequest(
      String path,
      String action,
      String method,
      bool shouldRetry,
      Map<String, dynamic> queryParameters,
      Map<String, dynamic> socketParameters,
      Map<String, dynamic>? bodyParameters) async {
    ResponseMessage response;
    try {
      response = await retry(
        () async {
          if (bodyParameters != null) {
            return _actionRest(
                path: path, method: method, bodyParameters: bodyParameters);
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
          throw UnexpectedError(message: 'Internet is or Server is offline');
        },
        maxAttempts: shouldRetry ? requestRetryLimit : 0,
        maxDelay: const Duration(seconds: 5),
        retryIf: (e) => e is! MetricsApiError && e is! UnexpectedError,
      );
    } on DioError catch (error) {
      throw UnexpectedError(message: error.message);
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

  void dequeue() async {
    if (_requestQueue.isEmpty) {
      return;
    }
    final request = _requestQueue.removeAt(0);
    try {
      final response = await executeRequest(
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
    }
  }

  Future<ResponseMessage> enqueue({
    required String path,
    required String action,
    required String method,
    bool shouldRetry = true,
    Map<String, dynamic> queryParameters = const {},
    Map<String, dynamic> socketParameters = const {},
    Map<String, dynamic>? bodyParameters,
  }) async {
    if (_activeRequest < concurrentRequestLimit) {
      _activeRequest++;
      try {
        final res = await executeRequest(path, action, method, shouldRetry,
            queryParameters, socketParameters, bodyParameters);
        return res;
      } finally {
        _activeRequest--;
        dequeue();
      }
    }
    final completer = Completer<ResponseMessage>();
    final requestHandler = RequestHandler(
        completer: completer,
        path: path,
        action: action,
        shouldRetry: shouldRetry,
        params: queryParameters,
        socketParams: socketParameters,
        bodyParams: bodyParameters,
        method: method);
    _requestQueue.add(requestHandler);
    final res = await completer.future;
    return res;
  }

  ResponseMessage _verifyAuthentication(ResponseMessage response) {
    final res = response.data as Map<String, dynamic>;
    if (res['accessToken'] != null) {
      _setAuthStatus(AuthenticationState.authenticated);
    }

    return response;
  }

  Future<ResponseMessage> _actionSocket(
      String action, Map<String, dynamic> params) async {
    final completer = Completer<ResponseMessage>();
    _lastMessageId++;
    final args = {
      'messageId': _lastMessageId,
      'event': 'action',
      'params': {
        'action': action,
        ...params,
      },
    };

    _completers[_lastMessageId] = completer;
    try {
      _socket?.sink.add(jsonEncode(args));
      final response = await completer.future;
      return response;
    } catch (error) {
      if (error is Map<String, dynamic>) {
        throw MetricsApiError.fromMap(error);
      }
      throw UnexpectedError(message: error.toString());
    }
  }

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
            ? FormData.fromMap(bodyParameters)
            : null,
      );
      _setServerStatus(ServerState.offline);
      return ResponseMessage(data: response.data);
    } on DioError catch (e) {
      if (shouldEnableErrorLogging) {
        print(e.message);
      }
      if (e.type == DioErrorType.connectTimeout) {
        _setServerStatus(ServerState.offline);
      } else if (e.type == DioErrorType.other) {
        if (e.message.contains('Connection Failed') ||
            e.message.contains('Connection failed') ||
            e.message.contains('Connection closed') ||
            e.message.contains('Connection refused')) {
          _setServerStatus(ServerState.offline);
        }
      } else if (e.type == DioErrorType.response ||
          (e.response != null && e.response!.data is Map<String, dynamic>)) {
        if ((e.response!.data as Map<String, dynamic>).containsKey('error')) {
          throw MetricsApiError.fromMap(e.response!.data['error']);
        }

        if (e.message.contains('Http status error [503]')) {
          _setServerStatus(ServerState.offline);
        }
      }
      rethrow;
    }
  }

  Future<ResponseMessage> chatRoomMessage(
      {required String room, required Map<String, dynamic> params}) async {
    // if (!initialized) {
    //   throw UnexpectedError(
    //       message:
    //           'User session hasn\'t been initialized. Please update user tokens');
    // }
    final completer = Completer<ResponseMessage>();
    _lastMessageId++;
    final args = {
      'messageId': _lastMessageId,
      'event': 'say',
      'room': room,
      'message': {
        'authorization': _accessToken,
        ...params,
      },
    };

    _completers[_lastMessageId] = completer;
    try {
      _socket?.sink.add(jsonEncode(args));
      final response = await completer.future;
      return response;
    } catch (error) {
      if (error is Map<String, dynamic>) {
        throw MetricsApiError.fromMap(error);
      }
      throw UnexpectedError(message: error.toString());
    }
  }

  Future<void> initializeAuthenticatedSession({required String token}) async {
    // if (initialized) {
    //   return;
    // }

    updateTokens(AuthenticatedResponse(accessToken: token));
    await _keepAlive(shouldThrow: true);
  }

  void updateTokens(AuthenticatedResponse authenticatedResponse) {
    //   initialized = true;
    _accessToken = authenticatedResponse.accessToken;

    if (_accessTokenTimer != null) {
      _accessTokenTimer!.cancel();
    }

    final tokenTTL = decodedAccesstoken!.exp * 1000 -
        DateTime.now().millisecondsSinceEpoch -
        jwtTTLLimit;
    _accessTokenTimer = Timer(Duration(milliseconds: tokenTTL), _keepAlive);

    if (authenticatedResponse.refreshToken != null) {
      _refreshToken = authenticatedResponse.refreshToken;
      _onRefreshChange
          .add(RefreshTokenChangeEvent(refreshToken: _refreshToken!));
    }
  }

  Future<void> _keepAlive({bool shouldThrow = false}) async {
    try {
      final response = await action(
          path: '/auth/keep-alive', action: 'auth:keepAlive', method: r'POST');
      final authenticatedResponse =
          AuthenticatedResponse.fromMap(response.data! as Map<String, dynamic>);
      updateTokens(authenticatedResponse);
    } catch (_) {
      if (shouldThrow) {
        rethrow;
      }
    }
  }

  Future<ResponseMessage> action({
    required String path,
    required String action,
    required String method,
    Map<String, dynamic> queryParameters = const {},
    Map<String, dynamic> socketParameters = const {},
    Map<String, dynamic>? bodyParameters,
  }) async {
    ResponseMessage? response;
    try {
      response = await enqueue(
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
      // if invalid token
      if (error.code == 616) {
        if (_refreshToken != null) {
          if (_isRefreshTokenInUse) {
            rethrow;
          }
          _isRefreshTokenInUse = true;
          try {
            response = await enqueue(
              action: action,
              queryParameters: {
                'authorization': _refreshToken,
                ...queryParameters,
              },
              method: method,
              path: path,
            );
          } on MetricsApiError catch (error) {
            // if blacklisted refresh token
            if (error.code == 615) {
              _setAuthStatus(
                AuthenticationState.unauthenticated,
              );
            }
            rethrow;
          } catch (_) {
            rethrow;
          } finally {
            _isRefreshTokenInUse = false;
          }
        } else {
          // invalid token and no refresh token
          _setAuthStatus(
            AuthenticationState.unauthenticated,
          );
          rethrow;
        }
      } else {
        rethrow;
      }
    } catch (_) {
      rethrow;
    }
    return _verifyAuthentication(response);
  }

  void dispose() async {
    close();
    await _onConnectionChange.close();
    await _onServerStatusChange.close();
    await _onAuthenticationStatusChange.close();
    await _onError.close();
    await _onRefreshChange.close();
  }
}
