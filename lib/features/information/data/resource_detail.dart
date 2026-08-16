import 'package:vilvia/features/information/data/resource.dart';

/// A single resource's full detail, as returned by
/// `GET /resources/{id}`: everything [Resource] already has, plus the full
/// article [body]. Kept as a separate, minimal type -- rather than adding
/// `body` to [Resource] -- so the Resources list model stays lightweight;
/// only the details screen ever needs the full body.
class ResourceDetail {
  const ResourceDetail({required this.resource, required this.body});

  final Resource resource;
  final String body;

  factory ResourceDetail.fromJson(Map<String, dynamic> json) {
    return ResourceDetail(
      // The detail response is a superset of the list response's fields,
      // so the same parsing logic applies unchanged.
      resource: Resource.fromJson(json),
      body: json['body'] as String,
    );
  }
}
