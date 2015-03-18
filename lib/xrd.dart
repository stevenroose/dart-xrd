/**
 * An implementation of Extensible Resource Descriptors with both XML and JSON support.
 *
 * The definition of Extensible Resource Descriptors can be found here:
 * http://docs.oasis-open.org/xri/xrd/v1.0/xrd-1.0.html.
 *
 * The JSON formatting of XRD documents is described here:
 * https://tools.ietf.org/html/rfc6415#appendix-A
 */
library xrd;

import "dart:convert";

import "package:collection/equality.dart";
import "package:collection/wrappers.dart";
import "package:xml/xml.dart";

class XrdDocument {
  static const String XML_NAMESPACE = "http://docs.oasis-open.org/ns/xri/xrd-1.0";
  static const String XML_NAMESPACE_NIL = "http://www.w3.org/2001/XMLSchema-instance";

  final String subject;
  final DateTime expires;
  final List<String> aliases;
  final List<XrdProperty> properties;
  final List<XrdLink> links;

  factory XrdDocument({String subject, DateTime expires, Iterable<String> aliases,
      dynamic /*Iterable<XRDProperty>|Map<String,String>*/ properties, Iterable<XrdLink> links}) {
    return new XrdDocument._internal(subject, expires, aliases != null ? new List.from(aliases) : null,
        _castProperties(properties), links != null ? new List.from(links) : null);
  }

  XrdDocument._internal(this.subject, this.expires, aliases, properties, links)
      : aliases = aliases != null ? new UnmodifiableListView(aliases) : null,
        properties = properties != null ? new UnmodifiableListView(properties) : null,
        links = links != null ? new UnmodifiableListView(links) : null;

  /**
   * Get the properties from the document in [Map] format.
   *
   * As defined in [Appendix A of RFC 6415](https://tools.ietf.org/html/rfc6415#appendix-A),
   * when multiple properties with the same type exist, only the last one is included in the map.
   */
  Map<String, String> get propertyMap => XrdProperty.convertPropertyListToMap(properties);

  /**
   * Get the property value for [type].
   *
   * [null] is returned if no property is found.
   */
  String property(String type) {
    XrdProperty prop = properties.lastWhere((XrdProperty p) => p.type == type, orElse: () => null);
    return prop != null ? prop.value : null;
  }

  /**
   * Find the preferred link with the given relation.
   *
   * The WebFinger protocol defines that if multiple links are provided with the same "rel", the first one
   * is the one preferred by the user.
   */
  XrdLink link(String rel) => links.firstWhere((l) => l.rel == rel, orElse: () => null);

  /**
   * Find all links with the given relation.
   */
  Iterable<XrdLink> allLinks(String rel) => links.where((l) => l.rel == rel);

  @override
  String toString() => "XRD document for $subject";

  @override
  bool operator ==(other) => other is XrdDocument &&
      const DeepCollectionEquality().equals([subject, expires, aliases, properties, links], [
    other.subject,
    other.expires,
    other.aliases,
    other.properties,
    other.links
  ]);

  @override
  int get hashCode => const DeepCollectionEquality().hash([subject, expires, aliases, properties, links]);

  /***************
   * JSON FORMAT *
   ***************/

  /**
   * Decode from the JSON format described in [RFC 6415](https://tools.ietf.org/html/rfc6415).
   */
  factory XrdDocument.fromJson(dynamic /*Map|String*/ json) {
    if (json is! Map) {
      json = const JsonDecoder().convert(json);
    }
    return new XrdDocument(
        subject: json["subject"],
        expires: json.containsKey("expires") ? DateTime.parse(json["expires"]) : null,
        aliases: json["aliases"],
        properties: json["properties"],
        links: json.containsKey("links") ? json["links"].map((l) => new XrdLink.fromJson(l)) : null);
  }

  /**
   * Encode to the JSON format described in [RFC 6415](https://tools.ietf.org/html/rfc6415).
   */
  Map<String, Object> toJSON() {
    Map<String, Object> json = new Map<String, Object>();
    if (subject != null) json["subject"] = subject;
    if (expires != null) json["expires"] = expires.toIso8601String();
    if (aliases != null) json["aliases"] = aliases;
    if (properties != null) json["properties"] = propertyMap;
    if (links != null) json["links"] = links.map((l) => l.toJson());
    return json;
  }

  /**************
   * XML format *
   **************/

  factory XrdDocument.fromXml(dynamic xml) {
    if (xml is! XmlDocument) {
      xml = parse(xml);
    }
    // reserve variables
    var subject, expires, aliases, properties, links;
    // parse
    XmlElement xrd = xml.findElements("XRD", namespace: XML_NAMESPACE).first;
    // test if xrd is only element
    if (xrd != xml.lastChild || (xml.firstChild != xrd && xml.firstChild.nodeType != XmlNodeType.PROCESSING)) {
      throw new FormatException("XRD document should contain exactly one <XRD> element");
    }
    // Subject
    Iterable<XmlElement> subjectElements = xrd.findElements("Subject");
    if (subjectElements.length == 1) {
      subject = subjectElements.first.text;
    } else if (subjectElements.length > 1) {
      throw new FormatException("XRD document should contain at most one <Subject> element");
    }
    // Expires
    Iterable<XmlElement> expiresElements = xrd.findElements("Expires");
    if (expiresElements.length == 1) {
      expires = DateTime.parse(expiresElements.first.text);
    } else if (expiresElements.length > 1) {
      throw new FormatException("XRD document should contain at most one <Expires> element");
    }
    // Alias
    Iterable<XmlElement> aliasElements = xrd.findElements("Alias");
    aliases = aliasElements.map((XmlElement e) => e.text);
    // Property
    Iterable<XmlElement> propertyElements = xrd.findElements("Property");
    properties = propertyElements.map(XrdProperty._fromXmlElement);
    // Link
    Iterable<XmlElement> linkElements = xrd.findElements("Link");
    links = linkElements.map((XmlElement e) => new XrdLink._fromXmlElement(e));
    return new XrdDocument(subject: subject, expires: expires, aliases: aliases, properties: properties, links: links);
  }

  XmlDocument toXml() {
    XmlBuilder builder = new XmlBuilder();
    builder.processing("xml", "version=\"1.0\" encoding=\"UTF-8\"");
    builder.element("XRD", namespaces: {}, nest: () {
      builder.namespace(XML_NAMESPACE);
      if (subject != null) {
        builder.element("Subject", nest: () => builder.text(subject));
      }
      if (expires != null) {
        builder.element("Expires", nest: () => builder.text(expires.toIso8601String()));
      }
      if (aliases != null) {
        aliases.forEach((String alias) {
          builder.element("Alias", nest: () => builder.text(alias));
        });
      }
      if (properties != null) {
        properties.forEach((XrdProperty prop) => prop._buildXml(builder));
      }
      if (links != null) {
        links.forEach((XrdLink link) => link._buildXml(builder));
      }
    });
    return builder.build();
  }
}

class XrdLink {
  final String rel;
  final String href;
  final String template;
  final String type;
  final Map<String, String> titles;
  final List<XrdProperty> properties;

  factory XrdLink({String rel, String href, String template, String type, Map<String, String> titles,
      dynamic /*Iterable<XrdProperty|Map<String,String>*/ properties}) {
    if (href != null && template != null) {
      throw new ArgumentError("An XRD Link element MUST NOT contain both a `href` and a `template` attribute");
    }
    return new XrdLink._internal(rel, href, template, type, titles, _castProperties(properties));
  }

  XrdLink._internal(this.rel, this.href, this.template, this.type, titles, properties)
      : titles = titles != null ? new UnmodifiableMapView(titles) : null,
        properties = properties != null ? new UnmodifiableListView(properties) : null;

  /**
   * Get the properties from the document in [Map] format.
   *
   * As defined in [Appendix A of RFC 6415](https://tools.ietf.org/html/rfc6415#appendix-A),
   * when multiple properties with the same type exist, only the last one is included in the map.
   */
  Map<String, String> get propertyMap => XrdProperty.convertPropertyListToMap(properties);

  /**
   * Get the property value for [type].
   *
   * [null] is returned if no property is found.
   */
  String property(String type) => properties.lastWhere((XrdProperty p) => p.type == type, orElse: () => null).value;

  /**
   * Build the resource-specific href using the resource URI and the template of this link.
   *
   * [null] is returned when [template] is also null.
   */
  String resourceSpecificHref(dynamic /*Uri|String*/ resource) {
    if (template != null) {
      return template.replaceAll("{uri}", resource.toString());
    } else if (href != null) {
      return href;
    } else {
      return null;
    }
  }

  @override
  String toString() => toJson().toString();

  @override
  bool operator ==(other) => other is XrdLink &&
      const DeepCollectionEquality().equals([rel, href, template, type, titles, properties], [
    other.rel,
    other.href,
    other.template,
    other.type,
    other.titles,
    other.properties
  ]);

  @override
  int get hashCode => const DeepCollectionEquality().hash([rel, href, template, type, titles, properties]);

  factory XrdLink.fromJson(Map json) => new XrdLink(
      rel: json["rel"],
      href: json["href"],
      template: json["template"],
      type: json["type"],
      titles: json["titles"],
      properties: json["properties"]);

  Map<String, Object> toJson() {
    Map<String, Object> json = new Map<String, Object>();
    if (rel != null) json["rel"] = rel;
    if (href != null) json["href"] = href;
    if (template != null) json["template"] = template;
    if (type != null) json["type"] = type;
    if (titles != null) json["titles"] = titles;
    if (properties != null) json["properties"] = propertyMap;
    return json;
  }

  factory XrdLink._fromXmlElement(XmlElement xml) {
    Map<String, String> titles = new Map<String, String>();
    xml.findElements("Title").forEach((XmlElement t) {
      String lang = t.getAttribute("xml:lang");
      if (lang == null) {
        titles["default"] = t.text;
      } else {
        titles[lang] = t.text;
      }
    });
    List<XrdProperty> properties = new List.from(xml.findElements("Property").map(XrdProperty._fromXmlElement));
    return new XrdLink(
        rel: xml.getAttribute("rel"),
        href: xml.getAttribute("href"),
        template: xml.getAttribute("template"),
        type: xml.getAttribute("type"),
        titles: titles,
        properties: properties);
  }

  XmlElement toXml() {
    XmlBuilder builder = new XmlBuilder();
    _buildXml(builder);
    return builder.build().firstChild;
  }

  void _buildXml(XmlBuilder builder) {
    Map attributes = new Map();
    if (rel != null) attributes["rel"] = rel;
    if (href != null) attributes["href"] = href;
    if (template != null) attributes["template"] = template;
    if (type != null) attributes["type"] = type;
    builder.element("Link", attributes: attributes, nest: () {
      if (properties != null) {
        properties.forEach((XrdProperty prop) => prop._buildXml(builder));
      }
      if (titles != null) {
        titles.forEach((String type, String value) {
          builder.element("Title", attributes: {"xml:lang": type}, nest: () => builder.text(value));
        });
      }
    });
  }
}

class XrdProperty {
  final String type;
  final String value;

  const XrdProperty(this.type, this.value);

  @override
  String toString() => "$type: $value";

  @override
  bool operator ==(other) =>
      other is XrdProperty && const DeepCollectionEquality().equals([type, value], [other.type, other.value]);

  @override
  int get hashCode => const DeepCollectionEquality().hash([type, value]);

  void _buildXml(XmlBuilder builder) {
    if (value == null) {
      builder.namespace(XrdDocument.XML_NAMESPACE_NIL, "xsi");
      builder.element("Property", attributes: {"type": type, "xsi:nil": true});
    } else {
      builder.element("Property", attributes: {"type": type}, nest: () {
        builder.text(value);
      });
    }
  }

  static Map<String, String> convertPropertyListToMap(List<XrdProperty> properties) {
    if (properties == null) return null;
    Map<String, String> props = new Map<String, String>();
    properties.forEach((XrdProperty prop) {
      props[prop.type] = prop.value;
    });
    return props;
  }

  static List<XrdProperty> convertMapToPropertyList(Map<String, String> propertyMap) {
    return new List.from(propertyMap.keys.map((String type) => new XrdProperty(type, propertyMap[type])));
  }

  static XrdProperty _fromXmlElement(XmlElement e) {
    if (e.getAttribute("nil", namespace: XrdDocument.XML_NAMESPACE_NIL) == "true") {
      return new XrdProperty(e.getAttribute("type"), null);
    } else {
      return new XrdProperty(e.getAttribute("type"), e.text);
    }
  }
}

List<XrdProperty> _castProperties(dynamic properties) {
  if (properties == null) {
    return null;
  } else if (properties is List<XrdProperty>) {
    return properties;
  } else if (properties is Iterable<XrdProperty>) {
    return new List.from(properties);
  } else if (properties is Map<String, String>) {
    return XrdProperty.convertMapToPropertyList(properties);
  } else {
    throw new ArgumentError(
        "The properties parameter must be of the type Iterable<XRDProperty> or Map<String, String>.");
  }
}
