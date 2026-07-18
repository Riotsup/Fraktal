#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "fraktal_opcua_bridge.h"

#include "open62541.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace {

constexpr size_t kMaxBrowseNodes = 20000;
constexpr unsigned kMaxBrowseDepth = 20;
constexpr size_t kBrowseBatchSize = 128;
constexpr size_t kReadBatchSize = 256;

struct NodeIdOwner {
  UA_NodeId value = UA_NODEID_NULL;

  NodeIdOwner() = default;
  explicit NodeIdOwner(const UA_NodeId& source) { UA_NodeId_copy(&source, &value); }
  NodeIdOwner(const NodeIdOwner&) = delete;
  NodeIdOwner& operator=(const NodeIdOwner&) = delete;
  NodeIdOwner(NodeIdOwner&& other) noexcept : value(other.value) {
    other.value = UA_NODEID_NULL;
  }
  NodeIdOwner& operator=(NodeIdOwner&& other) noexcept {
    if(this != &other) {
      UA_NodeId_clear(&value);
      value = other.value;
      other.value = UA_NODEID_NULL;
    }
    return *this;
  }
  ~NodeIdOwner() { UA_NodeId_clear(&value); }
};

struct ClientContext {
  UA_Client* client = nullptr;
  bool connected = false;
  bool discoveryComplete = false;
  bool discoveryTruncated = false;
  size_t discoveredNodeCount = 0;
  size_t staleNodeCount = 0;        // cached vars that no longer resolve (per read)
  std::string lastError;
  std::unordered_map<std::string, NodeIdOwner> nodes;
  std::vector<std::string> variablePaths;
  // Stored connect credentials so a dropped OPC UA session (a PLC online change
  // reloads the TF6100 namespace and tears the session down) can be re-established
  // without a Dart round-trip.
  std::string endpoint;
  std::string username;
  std::string password;
  uint32_t timeoutMs = 5000;

  ~ClientContext() {
    if(client != nullptr) {
      UA_Client_disconnect(client);
      UA_Client_delete(client);
    }
  }
};

std::string uaString(const UA_String& value) {
  if(value.data == nullptr || value.length == 0) return {};
  return std::string(reinterpret_cast<const char*>(value.data), value.length);
}

void jsonEscaped(std::ostringstream& out, const std::string& value) {
  out << '"';
  for(const unsigned char ch : value) {
    switch(ch) {
      case '"': out << "\\\""; break;
      case '\\': out << "\\\\"; break;
      case '\b': out << "\\b"; break;
      case '\f': out << "\\f"; break;
      case '\n': out << "\\n"; break;
      case '\r': out << "\\r"; break;
      case '\t': out << "\\t"; break;
      default:
        if(ch < 0x20) {
          static const char hex[] = "0123456789abcdef";
          out << "\\u00" << hex[(ch >> 4) & 0x0f] << hex[ch & 0x0f];
        } else {
          out << static_cast<char>(ch);
        }
    }
  }
  out << '"';
}

std::string nodeKey(const UA_NodeId& id) {
  UA_String printed = UA_STRING_NULL;
  if(UA_NodeId_print(&id, &printed) != UA_STATUSCODE_GOOD) return {};
  const std::string result = uaString(printed);
  UA_String_clear(&printed);
  return result;
}

// A cached NodeId that no longer resolves: the PLC address space changed under
// us (a symbol added/removed/renamed by an online change). Such reads are the
// signal to invalidate the discovery cache and re-browse next snapshot.
bool nodeGone(UA_StatusCode status) {
  return status == UA_STATUSCODE_BADNODEIDUNKNOWN ||
         status == UA_STATUSCODE_BADNODEIDINVALID;
}

template <typename T>
void numberArray(std::ostringstream& out, const UA_Variant& variant) {
  const auto* values = static_cast<const T*>(variant.data);
  out << '[';
  for(size_t i = 0; i < variant.arrayLength; ++i) {
    if(i != 0) out << ',';
    out << +values[i];
  }
  out << ']';
}

bool scalarJson(std::ostringstream& out, const UA_Variant& value) {
  if(value.data == nullptr || value.type == nullptr) {
    out << "null";
    return true;
  }
  const bool scalar = UA_Variant_isScalar(&value);
  if(!scalar) {
    if(value.type == &UA_TYPES[UA_TYPES_BOOLEAN]) {
      const auto* values = static_cast<const UA_Boolean*>(value.data);
      out << '[';
      for(size_t i = 0; i < value.arrayLength; ++i) {
        if(i != 0) out << ',';
        out << (values[i] ? "true" : "false");
      }
      out << ']';
      return true;
    }
    if(value.type == &UA_TYPES[UA_TYPES_SBYTE]) { numberArray<UA_SByte>(out, value); return true; }
    if(value.type == &UA_TYPES[UA_TYPES_BYTE]) { numberArray<UA_Byte>(out, value); return true; }
    if(value.type == &UA_TYPES[UA_TYPES_INT16]) { numberArray<UA_Int16>(out, value); return true; }
    if(value.type == &UA_TYPES[UA_TYPES_UINT16]) { numberArray<UA_UInt16>(out, value); return true; }
    if(value.type == &UA_TYPES[UA_TYPES_INT32]) { numberArray<UA_Int32>(out, value); return true; }
    if(value.type == &UA_TYPES[UA_TYPES_UINT32]) { numberArray<UA_UInt32>(out, value); return true; }
    if(value.type == &UA_TYPES[UA_TYPES_INT64]) { numberArray<UA_Int64>(out, value); return true; }
    if(value.type == &UA_TYPES[UA_TYPES_UINT64]) { numberArray<UA_UInt64>(out, value); return true; }
    if(value.type == &UA_TYPES[UA_TYPES_FLOAT]) { numberArray<UA_Float>(out, value); return true; }
    if(value.type == &UA_TYPES[UA_TYPES_DOUBLE]) { numberArray<UA_Double>(out, value); return true; }
    if(value.type == &UA_TYPES[UA_TYPES_STRING]) {
      const auto* values = static_cast<const UA_String*>(value.data);
      out << '[';
      for(size_t i = 0; i < value.arrayLength; ++i) {
        if(i != 0) out << ',';
        jsonEscaped(out, uaString(values[i]));
      }
      out << ']';
      return true;
    }
    return false;
  }

  if(value.type == &UA_TYPES[UA_TYPES_BOOLEAN]) {
    out << (*static_cast<const UA_Boolean*>(value.data) ? "true" : "false");
  } else if(value.type == &UA_TYPES[UA_TYPES_SBYTE]) {
    out << +*static_cast<const UA_SByte*>(value.data);
  } else if(value.type == &UA_TYPES[UA_TYPES_BYTE]) {
    out << +*static_cast<const UA_Byte*>(value.data);
  } else if(value.type == &UA_TYPES[UA_TYPES_INT16]) {
    out << *static_cast<const UA_Int16*>(value.data);
  } else if(value.type == &UA_TYPES[UA_TYPES_UINT16]) {
    out << *static_cast<const UA_UInt16*>(value.data);
  } else if(value.type == &UA_TYPES[UA_TYPES_INT32]) {
    out << *static_cast<const UA_Int32*>(value.data);
  } else if(value.type == &UA_TYPES[UA_TYPES_UINT32]) {
    out << *static_cast<const UA_UInt32*>(value.data);
  } else if(value.type == &UA_TYPES[UA_TYPES_INT64]) {
    out << *static_cast<const UA_Int64*>(value.data);
  } else if(value.type == &UA_TYPES[UA_TYPES_UINT64]) {
    out << *static_cast<const UA_UInt64*>(value.data);
  } else if(value.type == &UA_TYPES[UA_TYPES_FLOAT]) {
    out << *static_cast<const UA_Float*>(value.data);
  } else if(value.type == &UA_TYPES[UA_TYPES_DOUBLE]) {
    out << *static_cast<const UA_Double*>(value.data);
  } else if(value.type == &UA_TYPES[UA_TYPES_STRING] ||
            value.type == &UA_TYPES[UA_TYPES_BYTESTRING]) {
    jsonEscaped(out, uaString(*static_cast<const UA_String*>(value.data)));
  } else if(value.type == &UA_TYPES[UA_TYPES_LOCALIZEDTEXT]) {
    jsonEscaped(out, uaString(static_cast<const UA_LocalizedText*>(value.data)->text));
  } else if(value.type == &UA_TYPES[UA_TYPES_QUALIFIEDNAME]) {
    jsonEscaped(out, uaString(static_cast<const UA_QualifiedName*>(value.data)->name));
  } else if(value.type == &UA_TYPES[UA_TYPES_DATETIME]) {
    out << *static_cast<const UA_DateTime*>(value.data);
  } else if(value.type == &UA_TYPES[UA_TYPES_STATUSCODE]) {
    out << *static_cast<const UA_StatusCode*>(value.data);
  } else {
    return false;
  }
  return true;
}

bool shouldTraverse(const UA_ReferenceDescription& ref, unsigned depth) {
  if(ref.nodeId.serverIndex != 0) return false;
  // Namespace-zero children under Objects are server infrastructure. Fraktal
  // application symbols live in a vendor/application namespace.
  if(depth == 0 && ref.browseName.namespaceIndex == 0) return false;
  return ref.nodeClass == UA_NODECLASS_OBJECT ||
         ref.nodeClass == UA_NODECLASS_VARIABLE;
}

struct PendingBrowseNode {
  NodeIdOwner node;
  std::string path;
  unsigned depth;

  PendingBrowseNode(const UA_NodeId& source,
                    std::string browsePath,
                    unsigned browseDepth)
      : node(source), path(std::move(browsePath)), depth(browseDepth) {}
};

bool discover(ClientContext& context) {
  context.nodes.clear();
  context.variablePaths.clear();
  context.discoveredNodeCount = 0;
  context.discoveryTruncated = false;

  std::unordered_set<std::string> visited;
  std::vector<PendingBrowseNode> pending;
  const UA_NodeId objects = UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER);
  visited.insert(nodeKey(objects));
  pending.emplace_back(objects, "", 0);

  size_t cursor = 0;
  size_t batchLimit = kBrowseBatchSize;
  while(cursor < pending.size() &&
        context.discoveredNodeCount < kMaxBrowseNodes) {
    const size_t batchSize =
        std::min(batchLimit, pending.size() - cursor);
    UA_BrowseRequest request;
    UA_BrowseRequest_init(&request);
    request.requestedMaxReferencesPerNode = 0;
    request.nodesToBrowse = static_cast<UA_BrowseDescription*>(
        UA_Array_new(batchSize, &UA_TYPES[UA_TYPES_BROWSEDESCRIPTION]));
    request.nodesToBrowseSize = batchSize;
    for(size_t i = 0; i < batchSize; ++i) {
      UA_BrowseDescription& description = request.nodesToBrowse[i];
      UA_NodeId_copy(&pending[cursor + i].node.value, &description.nodeId);
      description.browseDirection = UA_BROWSEDIRECTION_FORWARD;
      description.referenceTypeId =
          UA_NODEID_NUMERIC(0, UA_NS0ID_HIERARCHICALREFERENCES);
      description.includeSubtypes = true;
      description.resultMask = UA_BROWSERESULTMASK_ALL;
    }

    UA_BrowseResponse response =
        UA_Client_Service_browse(context.client, request);
    UA_BrowseRequest_clear(&request);
    const UA_StatusCode serviceResult = response.responseHeader.serviceResult;
    if(serviceResult == UA_STATUSCODE_BADTOOMANYOPERATIONS && batchSize > 1) {
      UA_BrowseResponse_clear(&response);
      batchLimit = std::max<size_t>(1, batchSize / 2);
      continue;
    }
    if(serviceResult != UA_STATUSCODE_GOOD) {
      context.lastError = std::string("Browse failed: ") +
                          UA_StatusCode_name(serviceResult);
      UA_BrowseResponse_clear(&response);
      return false;
    }

    const size_t resultCount = std::min(response.resultsSize, batchSize);
    for(size_t resultIndex = 0; resultIndex < resultCount; ++resultIndex) {
      // Appending children can reallocate pending, so never retain a reference
      // into the vector while processing this result.
      const std::string parentPath = pending[cursor + resultIndex].path;
      const unsigned parentDepth = pending[cursor + resultIndex].depth;
      const UA_BrowseResult& result = response.results[resultIndex];
      if(result.statusCode != UA_STATUSCODE_GOOD) continue;
      for(size_t i = 0;
          i < result.referencesSize &&
          context.discoveredNodeCount < kMaxBrowseNodes;
          ++i) {
        const UA_ReferenceDescription& ref = result.references[i];
        if(!shouldTraverse(ref, parentDepth)) continue;
        const std::string name = uaString(ref.browseName.name);
        if(name.empty()) continue;
        const UA_NodeId& child = ref.nodeId.nodeId;
        const std::string idKey = nodeKey(child);
        if(idKey.empty() || !visited.insert(idKey).second) continue;
        const std::string path = parentPath.empty()
                                     ? name
                                     : parentPath + "/" + name;
        ++context.discoveredNodeCount;
        context.nodes.emplace(path, NodeIdOwner(child));
        if(ref.nodeClass == UA_NODECLASS_VARIABLE)
          context.variablePaths.push_back(path);
        if(parentDepth < kMaxBrowseDepth)
          pending.emplace_back(child, path, parentDepth + 1);
      }
    }
    UA_BrowseResponse_clear(&response);
    cursor += batchSize;
  }

  context.discoveryTruncated =
      context.discoveredNodeCount >= kMaxBrowseNodes || cursor < pending.size();
  context.discoveryComplete = true;
  return true;
}

bool readCachedValues(ClientContext& context,
                      std::ostringstream& values,
                      bool& firstValue) {
  context.staleNodeCount = 0;
  size_t cursor = 0;
  size_t batchLimit = kReadBatchSize;
  while(cursor < context.variablePaths.size()) {
    const size_t batchSize =
        std::min(batchLimit, context.variablePaths.size() - cursor);
    UA_ReadRequest request;
    UA_ReadRequest_init(&request);
    request.nodesToRead = static_cast<UA_ReadValueId*>(
        UA_Array_new(batchSize, &UA_TYPES[UA_TYPES_READVALUEID]));
    request.nodesToReadSize = batchSize;
    for(size_t i = 0; i < batchSize; ++i) {
      const auto found = context.nodes.find(context.variablePaths[cursor + i]);
      if(found == context.nodes.end()) continue;
      UA_NodeId_copy(&found->second.value, &request.nodesToRead[i].nodeId);
      request.nodesToRead[i].attributeId = UA_ATTRIBUTEID_VALUE;
    }

    UA_ReadResponse response = UA_Client_Service_read(context.client, request);
    UA_ReadRequest_clear(&request);
    const UA_StatusCode serviceResult = response.responseHeader.serviceResult;
    if(serviceResult == UA_STATUSCODE_BADTOOMANYOPERATIONS && batchSize > 1) {
      UA_ReadResponse_clear(&response);
      batchLimit = std::max<size_t>(1, batchSize / 2);
      continue;
    }
    if(serviceResult != UA_STATUSCODE_GOOD) {
      context.lastError = std::string("Read failed: ") +
                          UA_StatusCode_name(serviceResult);
      UA_ReadResponse_clear(&response);
      return false;
    }

    const size_t resultCount = std::min(response.resultsSize, batchSize);
    for(size_t i = 0; i < resultCount; ++i) {
      const UA_DataValue& dataValue = response.results[i];
      if(!dataValue.hasValue || dataValue.status != UA_STATUSCODE_GOOD) {
        // A cached NodeId that no longer resolves means the PLC address space
        // changed under us (online change). Count it; a surge invalidates the
        // discovery cache so the next snapshot re-browses the fresh tree.
        if(nodeGone(dataValue.status)) ++context.staleNodeCount;
        continue;
      }
      std::ostringstream encoded;
      if(!scalarJson(encoded, dataValue.value)) continue;
      if(!firstValue) values << ',';
      firstValue = false;
      jsonEscaped(values, context.variablePaths[cursor + i]);
      values << ':' << encoded.str();
    }
    UA_ReadResponse_clear(&response);
    cursor += batchSize;
  }
  return true;
}

// Diagnostic view of every child directly under Objects, before any
// traversal filtering, so an empty snapshot names what the server offered.
void describeRootChildren(ClientContext& context, std::ostringstream& out) {
  UA_BrowseRequest request;
  UA_BrowseRequest_init(&request);
  request.requestedMaxReferencesPerNode = 0;
  request.nodesToBrowse = UA_BrowseDescription_new();
  request.nodesToBrowseSize = 1;
  request.nodesToBrowse[0].nodeId = UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER);
  request.nodesToBrowse[0].browseDirection = UA_BROWSEDIRECTION_FORWARD;
  request.nodesToBrowse[0].referenceTypeId =
      UA_NODEID_NUMERIC(0, UA_NS0ID_HIERARCHICALREFERENCES);
  request.nodesToBrowse[0].includeSubtypes = true;
  request.nodesToBrowse[0].resultMask = UA_BROWSERESULTMASK_ALL;
  UA_BrowseResponse response = UA_Client_Service_browse(context.client, request);
  UA_BrowseRequest_clear(&request);
  bool first = true;
  if(response.responseHeader.serviceResult == UA_STATUSCODE_GOOD) {
    for(size_t resultIndex = 0; resultIndex < response.resultsSize; ++resultIndex) {
      const UA_BrowseResult& result = response.results[resultIndex];
      for(size_t i = 0; i < result.referencesSize; ++i) {
        const UA_ReferenceDescription& ref = result.references[i];
        std::ostringstream item;
        item << ref.browseName.namespaceIndex << ':'
             << uaString(ref.browseName.name) << '(';
        switch(ref.nodeClass) {
          case UA_NODECLASS_OBJECT: item << "Object"; break;
          case UA_NODECLASS_VARIABLE: item << "Variable"; break;
          default: item << static_cast<int>(ref.nodeClass); break;
        }
        item << ')';
        if(!first) out << ',';
        first = false;
        jsonEscaped(out, item.str());
      }
    }
  }
  UA_BrowseResponse_clear(&response);
}

// Read the standard Server/NamespaceArray even when access control hides all
// application objects. This separates "NodeManager not loaded" from "loaded
// namespace is not browsable by this identity" in startup diagnostics.
void describeNamespaces(ClientContext& context, std::ostringstream& out) {
  UA_Variant value;
  UA_Variant_init(&value);
  const UA_StatusCode status = UA_Client_readValueAttribute(
      context.client,
      UA_NODEID_NUMERIC(0, UA_NS0ID_SERVER_NAMESPACEARRAY),
      &value);
  if(status == UA_STATUSCODE_GOOD &&
     UA_Variant_hasArrayType(&value, &UA_TYPES[UA_TYPES_STRING]) &&
     scalarJson(out, value)) {
    UA_Variant_clear(&value);
    return;
  }
  UA_Variant_clear(&value);
  out << "[]";
}

// Re-establish the OPC UA session with the cached credentials. Always clears the
// cached NodeId map: after a reconnect the browse paths may map to fresh NodeIds,
// so the next snapshot re-discovers. Returns whether a usable session is up.
bool reconnect(ClientContext& context) {
  if(context.endpoint.empty()) {
    context.lastError = "Reconnect attempted without a stored endpoint";
    return false;
  }
  if(context.client != nullptr) {
    UA_Client_disconnect(context.client);
    UA_Client_delete(context.client);
    context.client = nullptr;
  }
  context.client = UA_Client_new();
  if(context.client == nullptr) {
    context.lastError = "UA_Client_new failed";
    context.connected = false;
    return false;
  }
  UA_ClientConfig* config = UA_Client_getConfig(context.client);
  UA_StatusCode status = UA_ClientConfig_setDefault(config);
  if(status == UA_STATUSCODE_GOOD) {
    config->timeout = context.timeoutMs;
    if(!context.username.empty()) {
      status = UA_Client_connectUsername(context.client, context.endpoint.c_str(),
                                         context.username.c_str(),
                                         context.password.c_str());
    } else {
      status = UA_Client_connect(context.client, context.endpoint.c_str());
    }
  }
  context.connected = status == UA_STATUSCODE_GOOD;
  if(!context.connected) {
    context.lastError = std::string("Reconnect failed: ") + UA_StatusCode_name(status);
    context.nodes.clear();
    context.variablePaths.clear();
    context.discoveryComplete = false;
    context.discoveryTruncated = false;
    context.discoveredNodeCount = 0;
    return false;
  }
  context.lastError.clear();
  context.nodes.clear();
  context.variablePaths.clear();
  context.discoveryComplete = false;          // force a fresh browse after reconnect
  context.discoveryTruncated = false;
  context.discoveredNodeCount = 0;
  return true;
}

// Recover transparently from a dropped session. A PLC online change reloads the
// TF6100 namespace and tears the session down; open62541 only auto-reconnects
// when its event loop is pumped, and this client is driven by explicit service
// calls. So check the live state and reconnect here before each snapshot.
bool ensureSession(ClientContext& context) {
  if(!context.connected || context.client == nullptr) return reconnect(context);
  UA_SecureChannelState channelState = UA_SECURECHANNELSTATE_CLOSED;
  UA_SessionState sessionState = UA_SESSIONSTATE_CLOSED;
  UA_StatusCode connectStatus = UA_STATUSCODE_GOOD;
  UA_Client_getState(context.client, &channelState, &sessionState, &connectStatus);
  if(connectStatus != UA_STATUSCODE_GOOD ||
     sessionState != UA_SESSIONSTATE_ACTIVATED) {
    return reconnect(context);
  }
  return true;
}

template <typename T>
int32_t writeScalar(ClientContext* context,
                    const char* path,
                    const T& value,
                    const UA_DataType& type) {
  if(context == nullptr || !context->connected || path == nullptr) return 0;
  const auto found = context->nodes.find(path);
  if(found == context->nodes.end()) {
    context->lastError = std::string("Unknown browse path: ") + path;
    return 0;
  }
  const UA_StatusCode status = UA_Client_writeValueAttribute_scalar(
      context->client, found->second.value, &value, &type);
  if(status != UA_STATUSCODE_GOOD) {
    context->lastError = std::string("Write failed: ") + UA_StatusCode_name(status);
    return 0;
  }
  return 1;
}

}  // namespace

extern "C" {

FrkOpcUaHandle frk_opcua_create(void) {
  return new ClientContext();
}

void frk_opcua_destroy(FrkOpcUaHandle handle) {
  delete static_cast<ClientContext*>(handle);
}

int32_t frk_opcua_connect(FrkOpcUaHandle handle,
                          const char* endpoint,
                          const char* username,
                          const char* password,
                          uint32_t timeout_ms) {
  auto* context = static_cast<ClientContext*>(handle);
  if(context == nullptr || endpoint == nullptr) return 0;
  if(context->client != nullptr) {
    UA_Client_disconnect(context->client);
    UA_Client_delete(context->client);
  }
  context->client = UA_Client_new();
  if(context->client == nullptr) {
    context->lastError = "UA_Client_new failed";
    return 0;
  }
  UA_ClientConfig* config = UA_Client_getConfig(context->client);
  UA_StatusCode status = UA_ClientConfig_setDefault(config);
  if(status != UA_STATUSCODE_GOOD) {
    context->lastError = std::string("Client configuration failed: ") +
                         UA_StatusCode_name(status);
    return 0;
  }
  config->timeout = timeout_ms;
  if(username != nullptr && username[0] != '\0') {
    status = UA_Client_connectUsername(context->client, endpoint, username,
                                       password == nullptr ? "" : password);
  } else {
    status = UA_Client_connect(context->client, endpoint);
  }
  context->connected = status == UA_STATUSCODE_GOOD;
  if(!context->connected) {
    context->lastError = std::string("Connect failed: ") + UA_StatusCode_name(status);
    return 0;
  }
  context->lastError.clear();
  // Cache the credentials so a later reconnect (session dropped by a PLC online
  // change) is self-contained — no Dart round-trip, no lost endpoint.
  context->endpoint = endpoint;
  context->username = (username != nullptr) ? username : "";
  context->password = (password != nullptr) ? password : "";
  context->timeoutMs = timeout_ms;
  context->nodes.clear();
  context->variablePaths.clear();
  context->discoveryComplete = false;
  context->discoveryTruncated = false;
  context->discoveredNodeCount = 0;
  return 1;
}

void frk_opcua_disconnect(FrkOpcUaHandle handle) {
  auto* context = static_cast<ClientContext*>(handle);
  if(context == nullptr || context->client == nullptr) return;
  UA_Client_disconnect(context->client);
  context->connected = false;
  context->nodes.clear();
  context->variablePaths.clear();
  context->discoveryComplete = false;
  context->discoveryTruncated = false;
  context->discoveredNodeCount = 0;
}

int32_t frk_opcua_is_connected(FrkOpcUaHandle handle) {
  const auto* context = static_cast<const ClientContext*>(handle);
  return context != nullptr && context->connected ? 1 : 0;
}

const char* frk_opcua_last_error(FrkOpcUaHandle handle) {
  const auto* context = static_cast<const ClientContext*>(handle);
  return context == nullptr ? "Invalid OPC UA client handle" : context->lastError.c_str();
}

char* frk_opcua_snapshot_json(FrkOpcUaHandle handle) {
  auto* context = static_cast<ClientContext*>(handle);
  if(context == nullptr) return nullptr;
  std::ostringstream values;
  bool firstValue = true;
  context->lastError.clear();

  // Recover transparently from a dropped OPC UA session (a PLC online change
  // reloads the TF6100 namespace and tears the session down). ensureSession
  // reconnects with the cached endpoint and clears the NodeId cache, so the
  // fresh structure is re-browsed below.
  if(!ensureSession(*context)) return nullptr;

  // Lazy discovery: browse on first snapshot, or after a reconnect/cache clear.
  if(!context->discoveryComplete && !discover(*context)) return nullptr;
  // Read the cached variables. Any service-level read failure is treated as link
  // loss: reconnect now (clears the cache) and let the next snapshot rediscover,
  // rather than serving a stale/empty tree.
  if(!readCachedValues(*context, values, firstValue)) {
    reconnect(*context);
    return nullptr;
  }

  // Structural change with a SURVIVING session (online change that did not drop
  // the link): if too many cached NodeIds no longer resolve, the address space
  // changed under us. Invalidate the cache so the next snapshot re-browses.
  if(!context->variablePaths.empty() &&
     context->staleNodeCount * 5 >= context->variablePaths.size()) {
    context->discoveryComplete = false;
  }

  std::ostringstream rootChildren;
  describeRootChildren(*context, rootChildren);
  std::ostringstream namespaces;
  describeNamespaces(*context, namespaces);

  std::ostringstream document;
  document << "{\"protocol\":\"fraktal.opcua.snapshot.v1\",\"nodeCount\":"
           << context->discoveredNodeCount
           << ",\"truncated\":"
           << (context->discoveryTruncated ? "true" : "false")
           << ",\"rootChildren\":[" << rootChildren.str()
           << "],\"namespaces\":" << namespaces.str()
           << ",\"values\":{" << values.str() << "}}";
  const std::string text = document.str();
  auto* result = static_cast<char*>(std::malloc(text.size() + 1));
  if(result == nullptr) return nullptr;
  std::memcpy(result, text.c_str(), text.size() + 1);
  return result;
}

void frk_opcua_free_string(char* value) { std::free(value); }

int32_t frk_opcua_write_bool(FrkOpcUaHandle handle,
                             const char* browse_path,
                             int32_t value) {
  const UA_Boolean converted = value != 0;
  return writeScalar(static_cast<ClientContext*>(handle), browse_path, converted,
                     UA_TYPES[UA_TYPES_BOOLEAN]);
}

int32_t frk_opcua_write_int64(FrkOpcUaHandle handle,
                              const char* browse_path,
                              int64_t value) {
  const UA_Int64 converted = value;
  return writeScalar(static_cast<ClientContext*>(handle), browse_path, converted,
                     UA_TYPES[UA_TYPES_INT64]);
}

int32_t frk_opcua_write_int32(FrkOpcUaHandle handle,
                              const char* browse_path,
                              int32_t value) {
  const UA_Int32 converted = value;
  return writeScalar(static_cast<ClientContext*>(handle), browse_path, converted,
                     UA_TYPES[UA_TYPES_INT32]);
}

int32_t frk_opcua_write_uint32(FrkOpcUaHandle handle,
                               const char* browse_path,
                               uint32_t value) {
  const UA_UInt32 converted = value;
  return writeScalar(static_cast<ClientContext*>(handle), browse_path, converted,
                     UA_TYPES[UA_TYPES_UINT32]);
}

int32_t frk_opcua_write_double(FrkOpcUaHandle handle,
                               const char* browse_path,
                               double value) {
  const UA_Double converted = value;
  return writeScalar(static_cast<ClientContext*>(handle), browse_path, converted,
                     UA_TYPES[UA_TYPES_DOUBLE]);
}

int32_t frk_opcua_write_string(FrkOpcUaHandle handle,
                               const char* browse_path,
                               const char* value) {
  UA_String converted = UA_STRING(const_cast<char*>(value == nullptr ? "" : value));
  return writeScalar(static_cast<ClientContext*>(handle), browse_path, converted,
                     UA_TYPES[UA_TYPES_STRING]);
}

}  // extern "C"
