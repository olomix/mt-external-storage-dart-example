import 'dart:ffi';
import 'dart:typed_data';
import 'package:convert/convert.dart' as convert;
import 'package:ffi/ffi.dart';

final _q = BigInt.parse("21888242871839275222246405745257275088548364400416034343698204186575808495617");

class Hash {
  final Uint8List _data;

  Hash.zero() : _data = Uint8List(32);

  Hash.fromUint8List(this._data) {
    assert(_data.length == 32);
  }

  Hash.fromBigInt(BigInt i): _data = Uint8List(32) {
    if (i < BigInt.from(0)) {
      throw ArgumentError("BigInt must be positive");
    }

    if (i >= _q) {
      throw ArgumentError("BigInt must be less than $_q");
    }

    int bytes = (i.bitLength + 7) >> 3;
    final b = BigInt.from(256);
    for (int j = 0; j < bytes; j++) {
      _data[j] = i.remainder(b).toInt();
      i = i >> 8;
    }
  }

  Hash.fromHex(String h): _data = Uint8List(32) {
    if (h.length != 64) {
      throw ArgumentError("Hex string must be 64 characters long");
    }
    convert.hex.decode(h).asMap().forEach((i, b) {_data[i] = b;});
  }

  @override
  String toString() {
    return convert.hex.encode(_data);
  }

  BigInt toBigInt() {
    final b = BigInt.from(256);
    BigInt i = BigInt.from(0);
    for (int j = _data.length - 1; j >= 0 ; j--) {
      i = i * b + BigInt.from(_data[j]);
    }
    return i;
  }

  bool testBit(int n) {
    if (n < 0 || n >= _data.length * 8) {
      throw ArgumentError("n must be in range [0, ${_data.length * 8}]");
    }
    return _data[n~/8]&(1<<(n%8)) != 0;
  }

  @override
  bool operator ==(Object other) {
    if (other is Hash) {
      for (int i = 0; i < _data.length; i++) {
        if (_data[i] != other._data[i]) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll(_data);
}

enum NodeType {
  middle,
  leaf,
  empty,
}

class Node {
  NodeType _type;
  Hash? childL; // left child of a middle node.
  Hash? childR; // right child of a middle node.

  List<Hash>? entry; // data stored in a leaf node

  Node(this._type);

  Node.leaf(Hash k, Hash v): _type = NodeType.leaf {
    entry = List<Hash>.from([k, v]);
  }

  Node.middle(this.childL, this.childR): _type = NodeType.middle;

  Node.empty(): _type = NodeType.empty;

  Hash get key {
    switch (_type) {
      case NodeType.leaf:
        return poseidonHashHashes3(entry![0], entry![1], Hash.fromBigInt(BigInt.one));
      case NodeType.middle:
        return poseidonHashHashes2(childL!, childR!);
      default:
        return Hash.zero();
    }
  }

  @override
  String toString() {
    switch (_type) {
      case NodeType.leaf:
        return "leaf(${entry![0]}, ${entry![1]}) => $key";
      case NodeType.middle:
        return "middle($childL, $childR) => $key";
      default:
        return "empty";
    }
  }
}

class NotFound implements Exception {}
class NodeKeyAlreadyExists implements Exception {}
class EntryIndexAlreadyExists implements Exception {}
class ReachedMaxLevel implements Exception {}
class InvalidNodeFound implements Exception {}

abstract class Storage {
  Node get(Hash k);
  void put(Hash k, Node n);
  Hash getRoot();
  void setRoot(Hash r);
}

class MemoryStorage implements Storage {
  final Map<Hash, Node> _data = <Hash, Node>{};
  Hash? _root;

  @override
  Node get(Hash k) {
    final n = _data[k];
    // print("get $k => $n");
    if (n == null) {
      throw NotFound();
    }
    return n;
  }

  @override
  put(Hash k, Node n) {
    // print("put $k $n");
    _data[k] = n;
  }

  @override
  Hash getRoot() {
    if (_root == null) {
      return Hash.zero();
    }
    return _root!;
  }

  @override
  void setRoot(Hash r) {
    _root = r;
  }
}

class MerkleTree {
  Hash root;
  int maxLevels;
  Storage storage;

  MerkleTree(this.storage, this.maxLevels): root = storage.getRoot();

  void add(BigInt k, BigInt v) {
    final kHash = Hash.fromBigInt(k);
    final vHash = Hash.fromBigInt(v);
    final newNodeLeaf = Node.leaf(kHash, vHash);
    final path = _getPath(maxLevels, kHash);
    root = _addLeaf(newNodeLeaf, root, 0, path);
    storage.setRoot(root);
  }

  Hash _addLeaf(Node newLeaf, Hash key, int lvl, List<bool> path) {
    if (lvl > maxLevels - 1) {
      throw ArgumentError("lvl must be less than maxLevels");
    }
    // print("add leaf under key $key at level $lvl");
    final n = getNode(key);
    switch(n._type) {
      case NodeType.empty:
        return _addNode(newLeaf);
      case NodeType.leaf:
        final nKey = n.entry![0];
        // Check if leaf node found contains the leaf node we are
        // trying to add
        final newLeafKey = newLeaf.entry![0];
        if (newLeafKey == nKey) {
          throw EntryIndexAlreadyExists();
        }
        final pathOldLeaf = _getPath(maxLevels, nKey);
        // We need to push newLeaf down until its path diverges from
        // n's path
        return _pushLeaf(newLeaf, n, lvl, path, pathOldLeaf);
      case NodeType.middle:
        // We need to go deeper, continue traversing the tree, left or
        // right depending on path
        late final Node newNodeMiddle;
        if (path[lvl]) { // go right
          final nextKey = _addLeaf(newLeaf, n.childR!, lvl+1, path);
          newNodeMiddle = Node.middle(n.childL!, nextKey);
        } else { // go left
          final nextKey = _addLeaf(newLeaf, n.childL!, lvl+1, path);
          newNodeMiddle = Node.middle(nextKey, n.childR!);
        }
        return _addNode(newNodeMiddle);
      default:
        throw InvalidNodeFound();
    }
  }

  Hash _addNode(Node n) {
    // print("add node $n");

    final k = n.key;
    if (n._type == NodeType.empty) {
      return k;
    }

    bool nodeFound = true;
    try {
      storage.get(k);
    } on NotFound {
      nodeFound = false;
    }

    if (nodeFound) {
      throw NodeKeyAlreadyExists();
    }

    storage.put(k, n);
    return k;
  }

  Node getNode(Hash key) {
    // print("get node key: $key");
    if (key == Hash.zero()) {
      return Node.empty();
    }
    return storage.get(key);
  }

  // pushLeaf recursively pushes an existing oldLeaf down until its path diverges
  // from newLeaf, at which point both leafs are stored, all while updating the
  // path.
  Hash _pushLeaf(Node newLeaf, Node oldLeaf, int lvl, List<bool> pathNewLeaf,
      List<bool> pathOldLeaf) {

    if (lvl > maxLevels - 2) {
      throw ReachedMaxLevel();
    }

    if (pathNewLeaf[lvl] == pathOldLeaf[lvl]) { // We need to go deeper!
      final nextKey = _pushLeaf(newLeaf, oldLeaf, lvl+1, pathNewLeaf,
          pathOldLeaf);
      late final Node newNodeMiddle;
      if (pathNewLeaf[lvl]) { // go right
        newNodeMiddle = Node.middle(Hash.zero(), nextKey);
      } else { // go left
        newNodeMiddle = Node.middle(nextKey, Hash.zero());
      }
      return _addNode(newNodeMiddle);
    }

    final oldLeafKey = oldLeaf.key;
    final newLeafKey = newLeaf.key;
    late final Node newNodeMiddle;
    if (pathNewLeaf[lvl]) {
      newNodeMiddle = Node.middle(oldLeafKey, newLeafKey);
    } else {
      newNodeMiddle = Node.middle(newLeafKey, oldLeafKey);
    }

    _addNode(newLeaf);
    return _addNode(newNodeMiddle);
  }
}

List<bool> _getPath(int numLevel, Hash h) {
  final path = List<bool>.filled(numLevel, false);
  for (int i = 0; i < numLevel; i++) {
    path[i] = h.testBit(i);
  }
  return path;
}

final libbabyjubjub = DynamicLibrary.open("/Users/alek/src/polygonid-flutter-sdk/rust/target/debug/libbabyjubjub.dylib");
final cstringFree = libbabyjubjub.lookupFunction<
    Void Function(Pointer<Utf8>),
    void Function(Pointer<Utf8>)>("cstring_free");
final _poseidonHash = libbabyjubjub.lookupFunction<
    Pointer<Utf8> Function(Pointer<Utf8>),
    Pointer<Utf8> Function(Pointer<Utf8>)>("poseidon_hash");
String poseidonHash(String input) {
  final ptr1 = input.toNativeUtf8();
  try {
    final resultPtr = _poseidonHash(ptr1);
    String resultString = resultPtr.toDartString();
    print("got string: $resultString");
    resultString = resultString.replaceAll("Fr(", "");
    resultString = resultString.replaceAll(")", "");
    cstringFree(resultPtr);
    return resultString;
  } catch (e) {
    print("error: $e");
    return "";
  }
}

final _poseidonHash3 = libbabyjubjub.lookupFunction<
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)>("hash_poseidon");
String __poseidonHash3(String v0, String v1, String v2) {
  final ptr0 = v0.toNativeUtf8();
  final ptr1 = v1.toNativeUtf8();
  final ptr2 = v2.toNativeUtf8();
  try {
    final resultPtr = _poseidonHash3(ptr0, ptr1, ptr2);
    String resultString = resultPtr.toDartString();
    resultString = resultString.replaceAll("Fr(", "");
    resultString = resultString.replaceAll(")", "");
    cstringFree(resultPtr);
    return resultString;
  } catch (e) {
    return "";
  }
}

final _poseidonHash2 = libbabyjubjub.lookupFunction<
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>("hash2_poseidon");
String __poseidonHash2(String v0, String v1) {
  final ptr0 = v0.toNativeUtf8();
  final ptr1 = v1.toNativeUtf8();
  try {
    final resultPtr = _poseidonHash2(ptr0, ptr1);
    String resultString = resultPtr.toDartString();
    resultString = resultString.replaceAll("Fr(", "");
    resultString = resultString.replaceAll(")", "");
    cstringFree(resultPtr);
    return resultString;
  } catch (e) {
    return "";
  }
}

BigInt poseidonHashInts2(BigInt a, BigInt b) {
  final h = __poseidonHash2(a.toRadixString(10), b.toRadixString(10));
  final h2 = Uint8List.fromList(convert.hex.decode(h));
  // rust implementation of poseidon returns int in big endian, no swapping
  // final h3 = _swap(h2);
  final i =  BigInt.tryParse(convert.hex.encode(h2), radix: 16);
  if (i == null) {
    throw ArgumentError("Could not parse hash");
  }
  return i;
}

BigInt poseidonHashInts3(BigInt a, BigInt b, BigInt c) {
  final h = __poseidonHash3(a.toRadixString(10), b.toRadixString(10),
      c.toRadixString(10));
  final h2 = Uint8List.fromList(convert.hex.decode(h));
  // rust implementation of poseidon returns int in big endian, no swapping
  // final h3 = _swap(h2);
  final i =  BigInt.tryParse(convert.hex.encode(h2), radix: 16);
  if (i == null) {
    throw ArgumentError("Could not parse hash");
  }
  return i;
}

Hash poseidonHashHashes2(Hash a, Hash b) {
  return Hash.fromBigInt(poseidonHashInts2(a.toBigInt(), b.toBigInt()));
}

Hash poseidonHashHashes3(Hash a, Hash b, Hash c) {
  return Hash.fromBigInt(
      poseidonHashInts3(a.toBigInt(), b.toBigInt(), c.toBigInt()));
}

Uint8List _swap(Uint8List a) {
  final x = List<int>.filled(a.length, 0);
  a.asMap().forEach((idx, elm) => { x[a.length - 1 - idx] = elm});
  return Uint8List.fromList(x);
}