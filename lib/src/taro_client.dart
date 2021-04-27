// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:js' as js;

import 'base_client.dart';
import 'base_request.dart';
import 'byte_stream.dart';
import 'exception.dart';
import 'streamed_response.dart';

const bool isTaro =
    bool.fromEnvironment('mpcore.env.taro', defaultValue: false);

/// Create a [BrowserClient].
///
/// Used from conditional imports, matches the definition in `client_stub.dart`.
BaseClient createClient() => TaroClient();

/// A `dart:html`-based HTTP client that runs in the browser and is backed by
/// XMLHttpRequests.
///
/// This client inherits some of the limitations of XMLHttpRequest. It ignores
/// the [BaseRequest.contentLength], [BaseRequest.persistentConnection],
/// [BaseRequest.followRedirects], and [BaseRequest.maxRedirects] fields. It is
/// also unable to stream requests or responses; a request will only be sent and
/// a response will only be returned once all the data is available.
class TaroClient extends BaseClient {
  js.JsObject? requestTask;

  /// Whether to send credentials such as cookies or authorization headers for
  /// cross-site requests.
  ///
  /// Defaults to `false`.
  bool withCredentials = false;

  /// Sends an HTTP request and asynchronously returns the response.
  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    var bytes = await request.finalize().bytesToString();

    var completer = Completer<StreamedResponse>();

    requestTask = (js.context['Taro'] as js.JsObject).callMethod('request', [
      js.JsObject.jsify({
        'url': request.url.toString(),
        'method': request.method,
        'header': request.headers,
        'responseType': 'arraybuffer',
        'data': bytes,
        'success': (response) {
          final body = base64.decode((js.context['Taro'] as js.JsObject)
              .callMethod('arrayBufferToBase64', [response['data']]) as String);
          final headers = <String, String>{};
          if (response['header'] is js.JsObject) {
            _JsMap(response['header'] as js.JsObject).forEach((key, value) {
              if (value is String) {
                headers[key] = value;
              }
            });
          }
          completer.complete(
            StreamedResponse(
              ByteStream.fromBytes(body),
              response['statusCode'] as int,
              contentLength: body.length,
              request: request,
              headers: headers,
              reasonPhrase: '',
            ),
          );
        },
        'fail': (error) {
          completer.completeError(
            ClientException(error.toString(), request.url),
            StackTrace.current,
          );
        },
      }),
    ]) as js.JsObject;

    try {
      return await completer.future;
    } finally {}
  }

  @override
  void close() {
    requestTask?.callMethod('abort');
  }
}

class _JsMap with MapMixin<String, dynamic> {
  final js.JsObject obj;

  _JsMap(this.obj);

  @override
  dynamic operator [](Object? key) {
    if (key == null) return null;
    return obj[key];
  }

  @override
  void operator []=(String key, value) {
    obj[key] = value;
  }

  @override
  void clear() {}

  @override
  Iterable<String> get keys =>
      ((js.context['Object'] as js.JsFunction).callMethod('keys', [obj])
              as js.JsArray)
          .toList()
          .cast<String>();

  @override
  dynamic remove(Object? key) {}
}
