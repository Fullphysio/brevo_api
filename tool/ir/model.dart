sealed class IrType {
  const IrType();
}

final class IrString extends IrType {
  const IrString();
}

final class IrInt extends IrType {
  const IrInt();
}

final class IrDouble extends IrType {
  const IrDouble();
}

final class IrBool extends IrType {
  const IrBool();
}

final class IrJson extends IrType {
  const IrJson();
}

final class IrJsonMap extends IrType {
  const IrJsonMap();
}

final class IrFile extends IrType {
  const IrFile();
}

final class IrList extends IrType {
  const IrList(this.element);
  final IrType element;
}

final class IrRef extends IrType {
  const IrRef(this.className);
  final String className;
}

final class IrEnumRef extends IrType {
  const IrEnumRef(this.enumName);
  final String enumName;
}

enum ClassKind { model, request }

final class FieldIr {
  const FieldIr({
    required this.wireName,
    required this.dartName,
    required this.type,
    required this.required,
    this.docs,
    this.deprecated = false,
    this.hasDateGetter = false,
  });

  final String wireName;
  final String dartName;
  final IrType type;
  final bool required;
  final String? docs;
  final bool deprecated;
  final bool hasDateGetter;
}

final class ClassIr {
  ClassIr({
    required this.className,
    required this.kind,
    required this.group,
    required this.fields,
    this.docs,
    this.origin,
    this.multipart = false,
  });

  final String className;
  final ClassKind kind;
  final String group;
  final List<FieldIr> fields;
  final String? docs;
  final String? origin;
  final bool multipart;
}

final class EnumValueIr {
  const EnumValueIr({required this.wire, required this.dartName});
  final String wire;
  final String dartName;
}

final class EnumIr {
  const EnumIr({
    required this.enumName,
    required this.group,
    required this.values,
    this.docs,
  });
  final String enumName;
  final String group;
  final List<EnumValueIr> values;
  final String? docs;
}

sealed class ResponseIr {
  const ResponseIr();
}

final class VoidResponse extends ResponseIr {
  const VoidResponse();
}

final class ObjectResponse extends ResponseIr {
  const ObjectResponse(this.className);
  final String className;
}

final class ListResponse extends ResponseIr {
  const ListResponse(this.element);
  final IrType element;
}

final class BytesResponse extends ResponseIr {
  const BytesResponse();
}

final class ParamIr {
  const ParamIr({
    required this.wireName,
    required this.dartName,
    required this.type,
    required this.required,
    this.docs,
    this.defaultValue,
  });
  final String wireName;
  final String dartName;
  final IrType type;
  final bool required;
  final String? docs;
  final Object? defaultValue;
}

final class PagedIr {
  const PagedIr({required this.itemClass, required this.listWireName});
  final String itemClass;
  final String listWireName;
}

final class OperationIr {
  const OperationIr({
    required this.key,
    required this.namespace,
    required this.methodName,
    required this.httpMethod,
    required this.pathTemplate,
    required this.pathParams,
    required this.queryParams,
    required this.bodyClass,
    required this.bodyRequired,
    required this.response,
    this.paged,
    this.docs,
    this.deprecated = false,
  });

  final String key;
  final String namespace;
  final String methodName;
  final String httpMethod;
  final String pathTemplate;
  final List<ParamIr> pathParams;
  final List<ParamIr> queryParams;
  final String? bodyClass;
  final bool bodyRequired;
  final ResponseIr response;
  final PagedIr? paged;
  final String? docs;
  final bool deprecated;
}

final class NamespaceIr {
  NamespaceIr({required this.name, required this.className});
  final String name;
  final String className;
  final List<OperationIr> operations = [];
}

final class MockCaseIr {
  const MockCaseIr({
    required this.operationKey,
    required this.pathParams,
    required this.queryParams,
    required this.responseBody,
    required this.status,
  });
  final String operationKey;
  final Map<String, String> pathParams;
  final Map<String, String> queryParams;
  final Object? responseBody;
  final int status;
}

final class GeneratorIr {
  const GeneratorIr({
    required this.classes,
    required this.enums,
    required this.namespaces,
    required this.mockCases,
    required this.specDigest,
  });

  final Map<String, ClassIr> classes;
  final Map<String, EnumIr> enums;
  final Map<String, NamespaceIr> namespaces;
  final List<MockCaseIr> mockCases;
  final String specDigest;
}
