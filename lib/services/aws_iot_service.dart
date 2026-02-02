import 'dart:async';
import 'dart:convert';

import 'package:aws_common/aws_common.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import '../core/constants/aws_constants.dart';
import '../core/utils/logger.dart';

/// Result of certificate creation
class CreateCertificateResult {
  final String certificateArn;
  final String certificateId;
  final String certificatePem;
  final String privateKey;
  final String? publicKey;

  CreateCertificateResult({
    required this.certificateArn,
    required this.certificateId,
    required this.certificatePem,
    required this.privateKey,
    this.publicKey,
  });

  factory CreateCertificateResult.fromJson(Map<String, dynamic> json) {
    return CreateCertificateResult(
      certificateArn: json['certificateArn'] as String,
      certificateId: json['certificateId'] as String,
      certificatePem: json['certificatePem'] as String,
      privateKey: json['keyPair']['PrivateKey'] as String,
      publicKey: json['keyPair']['PublicKey'] as String?,
    );
  }
}

/// Result of thing creation
class CreateThingResult {
  final String thingName;
  final String thingArn;
  final String? thingId;

  CreateThingResult({
    required this.thingName,
    required this.thingArn,
    this.thingId,
  });

  factory CreateThingResult.fromJson(Map<String, dynamic> json) {
    return CreateThingResult(
      thingName: json['thingName'] as String,
      thingArn: json['thingArn'] as String,
      thingId: json['thingId'] as String?,
    );
  }
}

/// Certificate description from describe certificate response
class CertificateDescription {
  final String certificateArn;
  final String certificateId;
  final String status;
  final String? certificatePem;
  final DateTime? creationDate;

  CertificateDescription({
    required this.certificateArn,
    required this.certificateId,
    required this.status,
    this.certificatePem,
    this.creationDate,
  });
}

/// Thing attribute from list response
class ThingAttribute {
  final String thingName;
  final String? thingArn;
  final String? thingTypeName;
  final Map<String, String> attributes;

  ThingAttribute({
    required this.thingName,
    this.thingArn,
    this.thingTypeName,
    this.attributes = const {},
  });

  factory ThingAttribute.fromJson(Map<String, dynamic> json) {
    return ThingAttribute(
      thingName: json['thingName'] as String,
      thingArn: json['thingArn'] as String?,
      thingTypeName: json['thingTypeName'] as String?,
      attributes: (json['attributes'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          {},
    );
  }
}

/// Service for interacting with AWS IoT APIs using HTTP + AWS Signature V4
/// This replaces the need for AWS CLI by making direct API calls
class AwsIotService {
  String? _region;
  String? _accessKeyId;
  String? _secretAccessKey;
  String? _sessionToken;
  String? _iotEndpoint;

  /// Initialize the service with AWS credentials
  void initialize({
    required String region,
    required String accessKeyId,
    required String secretAccessKey,
    String? sessionToken,
    String? iotEndpoint,
  }) {
    _region = region;
    _accessKeyId = accessKeyId;
    _secretAccessKey = secretAccessKey;
    _sessionToken = sessionToken;
    _iotEndpoint = iotEndpoint;

    AppLogger.info('AWS IoT service initialized for region: $region');
  }

  /// Check if the service is initialized
  bool get isInitialized =>
      _region != null && _accessKeyId != null && _secretAccessKey != null;

  void _ensureInitialized() {
    if (!isInitialized) {
      throw StateError(
        'AWS IoT service not initialized. Call initialize() first.',
      );
    }
  }

  /// Get the IoT control plane endpoint
  String get _controlPlaneEndpoint => 'iot.$_region.amazonaws.com';

  /// Make a signed request to AWS IoT API with retry logic
  Future<http.Response> _signedRequest({
    required String method,
    required String path,
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    int maxRetries = 3,
  }) async {
    _ensureInitialized();

    Exception? lastException;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      if (attempt > 0) {
        // Exponential backoff: 1s, 2s, 4s
        final delay = Duration(seconds: 1 << (attempt - 1));
        AppLogger.debug('Retry attempt $attempt after ${delay.inSeconds}s delay');
        await Future.delayed(delay);
      }

      // Build URI with query parameters
      // Let Uri.https handle the encoding naturally
      final Uri uri;
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = Uri.https(_controlPlaneEndpoint, path, queryParams);
        AppLogger.debug('URI with query: ${uri.toString()}');
        AppLogger.debug('URI query: ${uri.query}');
        AppLogger.debug('URI queryParameters: ${uri.queryParameters}');
      } else {
        uri = Uri.https(_controlPlaneEndpoint, path);
      }

      final request = http.Request(method, uri);
      request.headers['Host'] = _controlPlaneEndpoint;

      // Only set Content-Type if we have a body
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }

      // Add custom headers
      if (headers != null) {
        request.headers.addAll(headers);
      }

      // Sign the request with AWS Signature V4
      final signedRequest = await _signRequest(request);

      AppLogger.debug('Final request URL: ${signedRequest.url}');
      AppLogger.debug('Final request method: ${signedRequest.method}');
      AppLogger.debug('Final request headers: ${signedRequest.headers}');
      AppLogger.debug('Final request body length: ${signedRequest.body.length}');

      final client = http.Client();
      try {
        final streamedResponse = await client.send(signedRequest).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('Request timed out after 30 seconds');
          },
        );
        return await http.Response.fromStream(streamedResponse);
      } on TimeoutException catch (e) {
        lastException = e;
        AppLogger.warning('Request timeout on attempt ${attempt + 1}: $path');
      } on http.ClientException catch (e) {
        lastException = e;
        AppLogger.warning('Client error on attempt ${attempt + 1}: ${e.message}');
      } on Exception catch (e) {
        lastException = e;
        AppLogger.warning('Request error on attempt ${attempt + 1}: $e');
      } finally {
        client.close();
      }
    }

    throw lastException ?? Exception('Request failed after $maxRetries attempts');
  }

  /// Sign a request with AWS Signature V4
  Future<http.Request> _signRequest(http.Request request) async {
    final now = DateTime.now().toUtc();
    final dateStamp = _formatDate(now);
    final amzDate = _formatAmzDate(now);

    // Add required headers
    request.headers['X-Amz-Date'] = amzDate;
    if (_sessionToken != null) {
      request.headers['X-Amz-Security-Token'] = _sessionToken!;
    }

    // Create canonical request
    final canonicalUri = request.url.path.isEmpty ? '/' : request.url.path;
    final canonicalQueryString = _canonicalQueryString(request.url.queryParameters);
    final payloadHash = _hash(request.body);

    // Debug: compare query strings
    AppLogger.debug('request.url.query (raw): ${request.url.query}');
    AppLogger.debug('request.url.queryParameters: ${request.url.queryParameters}');
    AppLogger.debug('canonicalQueryString: $canonicalQueryString');

    final signedHeaders = _getSignedHeaders(request.headers);
    final canonicalHeaders = _getCanonicalHeaders(request.headers);

    final canonicalRequest = [
      request.method,
      canonicalUri,
      canonicalQueryString,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    // Create string to sign
    final algorithm = 'AWS4-HMAC-SHA256';
    final credentialScope = '$dateStamp/$_region/iot/aws4_request';
    final stringToSign = [
      algorithm,
      amzDate,
      credentialScope,
      _hash(canonicalRequest),
    ].join('\n');

    // Calculate signature
    final signingKey = _getSignatureKey(
      _secretAccessKey!,
      dateStamp,
      _region!,
      'iot',
    );
    final signature = _hmacHex(signingKey, stringToSign);

    // Add authorization header
    final authorizationHeader = [
      '$algorithm Credential=$_accessKeyId/$credentialScope',
      'SignedHeaders=$signedHeaders',
      'Signature=$signature',
    ].join(', ');

    request.headers['Authorization'] = authorizationHeader;

    return request;
  }

  String _formatDate(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  String _formatAmzDate(DateTime date) {
    return '${_formatDate(date)}T${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')}Z';
  }

  String _hash(String data) {
    return sha256.convert(utf8.encode(data)).toString();
  }

  List<int> _hmac(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).bytes;
  }

  String _hmacHex(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).toString();
  }

  List<int> _getSignatureKey(
    String key,
    String dateStamp,
    String region,
    String service,
  ) {
    final kDate = _hmac(utf8.encode('AWS4$key'), dateStamp);
    final kRegion = _hmac(kDate, region);
    final kService = _hmac(kRegion, service);
    final kSigning = _hmac(kService, 'aws4_request');
    return kSigning;
  }

  /// Build canonical query string for AWS Signature V4
  /// Must match exactly how the query appears in the actual HTTP request
  String _canonicalQueryString(Map<String, String> params) {
    if (params.isEmpty) return '';
    final sortedKeys = params.keys.toList()..sort();
    // Use the same encoding as Uri.https uses for query parameters
    // This ensures the canonical request matches the actual request
    final tempUri = Uri.https('temp', '/',
      Map.fromEntries(sortedKeys.map((k) => MapEntry(k, params[k]!))));
    return tempUri.query;
  }

  String _getSignedHeaders(Map<String, String> headers) {
    final sortedKeys = headers.keys.map((k) => k.toLowerCase()).toList()..sort();
    return sortedKeys.join(';');
  }

  String _getCanonicalHeaders(Map<String, String> headers) {
    final sortedKeys = headers.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final headerLines = sortedKeys
        .map((k) => '${k.toLowerCase()}:${headers[k]!.trim()}')
        .join('\n');
    return '$headerLines\n';
  }

  // ============ Endpoint Discovery ============

  /// Get the IoT data endpoint for the account
  Future<String> describeEndpoint() async {
    _ensureInitialized();

    final response = await _signedRequest(
      method: 'GET',
      path: '/endpoint',
      queryParams: {'endpointType': 'iot:Data-ATS'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get endpoint: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final endpoint = data['endpointAddress'] as String;

    _iotEndpoint = endpoint;
    AppLogger.info('Discovered IoT endpoint: $endpoint');
    return endpoint;
  }

  /// Get the current IoT endpoint
  String? get iotEndpoint => _iotEndpoint;

  // ============ Thing Operations ============

  /// Create a new thing
  Future<CreateThingResult> createThing({
    required String thingName,
    String? thingTypeName,
    Map<String, String>? attributes,
  }) async {
    _ensureInitialized();

    final body = <String, dynamic>{};
    if (thingTypeName != null) {
      body['thingTypeName'] = thingTypeName;
    }
    if (attributes != null && attributes.isNotEmpty) {
      body['attributePayload'] = {'attributes': attributes};
    }

    final response = await _signedRequest(
      method: 'POST',
      path: '/things/$thingName',
      body: body.isEmpty ? null : body,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create thing: ${response.body}');
    }

    AppLogger.info('Created thing: $thingName');
    return CreateThingResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Delete a thing
  Future<void> deleteThing(String thingName) async {
    _ensureInitialized();

    final response = await _signedRequest(
      method: 'DELETE',
      path: '/things/$thingName',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete thing: ${response.body}');
    }

    AppLogger.info('Deleted thing: $thingName');
  }

  /// Update thing attributes
  Future<void> updateThing({
    required String thingName,
    required Map<String, String> attributes,
  }) async {
    _ensureInitialized();

    final response = await _signedRequest(
      method: 'PATCH',
      path: '/things/$thingName',
      body: {
        'attributePayload': {'attributes': attributes},
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update thing: ${response.body}');
    }

    AppLogger.info('Updated thing: $thingName');
  }

  /// List things with optional filtering
  Future<List<ThingAttribute>> listThings({
    String? thingTypeName,
    int? maxResults,
    String? nextToken,
  }) async {
    _ensureInitialized();

    final queryParams = <String, String>{};
    if (thingTypeName != null) queryParams['thingTypeName'] = thingTypeName;
    if (maxResults != null) queryParams['maxResults'] = maxResults.toString();
    if (nextToken != null) queryParams['nextToken'] = nextToken;

    final response = await _signedRequest(
      method: 'GET',
      path: '/things',
      queryParams: queryParams.isEmpty ? null : queryParams,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to list things: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final things = (data['things'] as List<dynamic>?)
            ?.map((t) => ThingAttribute.fromJson(t as Map<String, dynamic>))
            .toList() ??
        [];

    return things;
  }

  // ============ Certificate Operations ============

  /// Create keys and certificate
  Future<CreateCertificateResult> createKeysAndCertificate({
    bool setAsActive = true,
  }) async {
    _ensureInitialized();

    final response = await _signedRequest(
      method: 'POST',
      path: '/keys-and-certificate',
      queryParams: {'setAsActive': setAsActive.toString()},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create certificate: ${response.body}');
    }

    AppLogger.info('Created certificate');
    return CreateCertificateResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Delete a certificate
  Future<void> deleteCertificate(
    String certificateId, {
    bool forceDelete = false,
  }) async {
    _ensureInitialized();

    final queryParams = <String, String>{};
    if (forceDelete) queryParams['forceDelete'] = 'true';

    final response = await _signedRequest(
      method: 'DELETE',
      path: '/certificates/$certificateId',
      queryParams: queryParams.isEmpty ? null : queryParams,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete certificate: ${response.body}');
    }

    AppLogger.info('Deleted certificate: $certificateId');
  }

  /// Update certificate status
  Future<void> updateCertificateStatus({
    required String certificateId,
    required String newStatus, // ACTIVE, INACTIVE, REVOKED
  }) async {
    _ensureInitialized();

    final response = await _signedRequest(
      method: 'PUT',
      path: '/certificates/$certificateId',
      queryParams: {'newStatus': newStatus},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update certificate status: ${response.body}');
    }

    AppLogger.info('Updated certificate $certificateId status to $newStatus');
  }

  // ============ Thing-Certificate Attachment ============

  /// Attach a certificate to a thing
  Future<void> attachThingPrincipal({
    required String thingName,
    required String principal, // Certificate ARN
  }) async {
    _ensureInitialized();

    final response = await _signedRequest(
      method: 'PUT',
      path: '/things/$thingName/principals',
      headers: {'x-amzn-principal': principal},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to attach principal: ${response.body}');
    }

    AppLogger.info('Attached principal to thing: $thingName');
  }

  /// Detach a certificate from a thing
  Future<void> detachThingPrincipal({
    required String thingName,
    required String principal,
  }) async {
    _ensureInitialized();

    final response = await _signedRequest(
      method: 'DELETE',
      path: '/things/$thingName/principals',
      headers: {'x-amzn-principal': principal},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to detach principal: ${response.body}');
    }

    AppLogger.info('Detached principal from thing: $thingName');
  }

  /// List principals (certificates) attached to a thing
  Future<List<String>> listThingPrincipals(String thingName) async {
    _ensureInitialized();

    final response = await _signedRequest(
      method: 'GET',
      path: '/things/$thingName/principals',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to list principals: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['principals'] as List<dynamic>?)
            ?.map((p) => p.toString())
            .toList() ??
        [];
  }

  /// Describe a certificate to get its details including PEM
  Future<CertificateDescription> describeCertificate(String certificateId) async {
    _ensureInitialized();

    final response = await _signedRequest(
      method: 'GET',
      path: '/certificates/$certificateId',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to describe certificate: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final certDesc = data['certificateDescription'] as Map<String, dynamic>;

    return CertificateDescription(
      certificateArn: certDesc['certificateArn'] as String,
      certificateId: certDesc['certificateId'] as String,
      status: certDesc['status'] as String,
      certificatePem: certDesc['certificatePem'] as String?,
      creationDate: certDesc['creationDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch((certDesc['creationDate'] as num).toInt() * 1000)
          : null,
    );
  }

  /// Get certificate ID from ARN
  String getCertificateIdFromArn(String arn) {
    // ARN format: arn:aws:iot:region:account:cert/certificate-id
    final parts = arn.split('/');
    return parts.length > 1 ? parts.last : arn;
  }

  // ============ Policy Operations ============

  /// Attach a policy to a certificate
  Future<void> attachPolicy({
    required String policyName,
    required String target, // Certificate ARN
  }) async {
    _ensureInitialized();

    AppLogger.debug('attachPolicy: policyName=$policyName, target=$target');

    if (target.isEmpty) {
      throw Exception('Certificate ARN (target) is empty');
    }

    // Target must be passed in the JSON body, not as a query parameter
    final response = await _signedRequest(
      method: 'PUT',
      path: '/target-policies/$policyName',
      body: {'target': target},
    );

    if (response.statusCode != 200) {
      AppLogger.debug('attachPolicy response: status=${response.statusCode}, body=${response.body}');
      throw Exception('Failed to attach policy: ${response.body}');
    }

    AppLogger.info('Attached policy $policyName to target');
  }

  /// Detach a policy from a certificate
  Future<void> detachPolicy({
    required String policyName,
    required String target,
  }) async {
    _ensureInitialized();

    // Target must be passed in the JSON body, not as a query parameter
    final response = await _signedRequest(
      method: 'POST',
      path: '/target-policies/$policyName:detach',
      body: {'target': target},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to detach policy: ${response.body}');
    }

    AppLogger.info('Detached policy $policyName from target');
  }

  // ============ High-Level Operations ============

  /// Create a complete thing with certificate and policy attachment
  Future<({CreateThingResult thing, CreateCertificateResult certificate})>
      createThingWithCertificate({
    required String thingName,
    required String environment,
    String? thingTypeName,
    Map<String, String>? attributes,
  }) async {
    // Create certificate first
    final cert = await createKeysAndCertificate();

    // Create thing
    final thing = await createThing(
      thingName: thingName,
      thingTypeName: thingTypeName,
      attributes: attributes,
    );

    // Attach certificate to thing
    await attachThingPrincipal(
      thingName: thingName,
      principal: cert.certificateArn,
    );

    // Attach policy to certificate
    final policyName = AwsConstants.iotPolicyName(environment);
    await attachPolicy(
      policyName: policyName,
      target: cert.certificateArn,
    );

    AppLogger.info('Created thing $thingName with certificate and policy');

    return (thing: thing, certificate: cert);
  }

  /// Delete a thing with its certificates
  Future<void> deleteThingWithCertificates(String thingName) async {
    // Get attached certificates
    final principals = await listThingPrincipals(thingName);

    for (final principal in principals) {
      // Detach from thing
      await detachThingPrincipal(thingName: thingName, principal: principal);

      // Extract certificate ID from ARN
      final certId = principal.split('/').last;

      // Deactivate certificate
      await updateCertificateStatus(
        certificateId: certId,
        newStatus: 'INACTIVE',
      );

      // Delete certificate
      await deleteCertificate(certId);
    }

    // Delete thing
    await deleteThing(thingName);

    AppLogger.info('Deleted thing $thingName with all certificates');
  }
}
