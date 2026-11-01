import 'dart:convert';

import 'package:dio/dio.dart';

import 'mcp_server.dart';

class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
}

/// Minimal Streamable HTTP MCP client used by the settings diagnostics.
/// It performs initialize + tools/list; the agent tool loop can reuse the same
/// JSON-RPC transport later.
class McpClient {
  McpClient(this.server);

  final McpServer server;

  Future<List<McpTool>> listTools() async {
    final dio = Dio(
      BaseOptions(
        baseUrl: server.url,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          if (server.token.isNotEmpty)
            'Authorization': 'Bearer ${server.token}',
        },
      ),
    );
    String? sessionId;

    Future<Map<String, dynamic>> rpc(
      int id,
      String method,
      Map<String, dynamic> params,
    ) async {
      final response = await dio.post<dynamic>(
        '',
        data: {
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': params,
        },
        options: Options(
          headers: {
            if (sessionId != null) 'Mcp-Session-Id': sessionId,
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final headerSession = response.headers.value('mcp-session-id');
      if (headerSession != null && headerSession.isNotEmpty) {
        sessionId = headerSession;
      }
      final decoded = _decode(response.data);
      final error = decoded['error'];
      if (error is Map) {
        throw StateError(error['message']?.toString() ?? 'MCP error');
      }
      final result = decoded['result'];
      return result is Map ? Map<String, dynamic>.from(result) : {};
    }

    await rpc(1, 'initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'ChatVivid', 'version': '0.1.0'},
    });
    // Notification, no JSON-RPC id.
    await dio.post<dynamic>(
      '',
      data: {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      options: Options(
        headers: {
          if (sessionId != null) 'Mcp-Session-Id': sessionId,
        },
      ),
    );
    final result = await rpc(2, 'tools/list', <String, dynamic>{});
    final raw = result['tools'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) {
      final schema = item['inputSchema'];
      return McpTool(
        name: (item['name'] ?? '').toString(),
        description: (item['description'] ?? '').toString(),
        inputSchema: schema is Map
            ? Map<String, dynamic>.from(schema)
            : <String, dynamic>{},
      );
    }).toList();
  }

  Map<String, dynamic> _decode(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      for (final line in const LineSplitter().convert(data)) {
        if (line.startsWith('data:')) {
          final payload = line.substring(5).trim();
          if (payload.isEmpty || payload == '[DONE]') continue;
          final decoded = jsonDecode(payload);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        }
      }
    }
    return <String, dynamic>{};
  }
}
