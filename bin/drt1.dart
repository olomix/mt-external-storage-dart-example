import 'dart:cli';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import '../generated_bindings.dart' as bindings;
import 'package:ffi/ffi.dart' as ffi2;
import 'package:sembast/sembast_io.dart' as sembast_io;
import 'package:sembast/sembast.dart' as sembast;
import 'package:convert/convert.dart' as convert;

// settings
final dylibPath = '/Users/alek/src/go-iden3-core-clib/ios/libiden3core.dylib';
final String dbPath = 'sample.db';
final String dbPrefix = '_pref';
// settings [end]

final dylib = ffi.DynamicLibrary.open(dylibPath);
final iden3lib = bindings.NativeLibrary(dylib);
final String dbRootKey = 'root';
sembast.Database? db;

bool get1(ffi.Pointer<ffi.Void> _, bindings.IDENByteArray key,
    ffi.Pointer<bindings.IDENByteArray> value) {

  value.ref.data = ffi.nullptr;
  value.ref.data_len = 0;

  if (db == null) {
    return false;
  }

  final keyStr = stringFromByteArray(key);
  final f = sembast.StoreRef(dbPrefix).record(keyStr).get(db!);

  try {
    final v = waitFor(f) as String?;
    if (v == null) {
      return false;
    }

    final dec = convert.hex.decode(v) as Uint8List;
    value.ref.data = ffi2.malloc(dec.length);
    for (int i = 0; i < dec.length; i++) {
      value.ref.data[i] = dec[i];
    }
    value.ref.data_len = dec.length;
    return true;
  } catch (e) {
    print("[dart] get error: $e");
    return false;
  }
}

bool put(ffi.Pointer<ffi.Void> _, bindings.IDENByteArray key,
    bindings.IDENByteArray value) {

  if (db == null) {
    return false;
  }

  final keyStr = stringFromByteArray(key);
  final valueStr = stringFromByteArray(value);

  try {
    waitFor(sembast.StoreRef(dbPrefix).record(keyStr).put(db!, valueStr));
    return true;
  } catch (e) {
    print("[dart] put error: $e");
    return false;
  }
}

bool getRoot(ffi.Pointer<ffi.Void> _, ffi.Pointer<bindings.IDENByteArray> ba) {
  if (db == null) {
    return false;
  }

  ba.ref.data = ffi.nullptr;
  ba.ref.data_len = 0;

  final f = sembast.StoreRef(dbPrefix).record(dbRootKey).get(db!);
  try {
    final v = waitFor(f) as String?;
    if (v == null) {
      ba.ref.data_len = 32;
      ba.ref.data = ffi2.calloc<ffi.UnsignedChar>(ba.ref.data_len);
      return true;
    }

    final dec = convert.hex.decode(v) as Uint8List;
    ba.ref.data = ffi2.calloc<ffi.UnsignedChar>(dec.length);
    for (int i = 0; i < dec.length; i++) {
      ba.ref.data[i] = dec[i];
    }
    ba.ref.data_len = dec.length;
    return true;
  } catch (e) {
    print("[dart] get_root error: $e");
    return false;
  }
}

bool setRoot(ffi.Pointer<ffi.Void> _, bindings.IDENByteArray ba) {
  if (db == null) {
    return false;
  }

  final valueStr = stringFromByteArray(ba);
  try {
    waitFor(sembast.StoreRef(dbPrefix).record(dbRootKey).put(db!, valueStr));
    return true;
  } catch (e) {
    print("[dart] set_root error: $e");
    return false;
  }
}

final get1CB = ffi.Pointer.fromFunction<
    ffi.Bool Function(ffi.Pointer<ffi.Void>, bindings.IDENByteArray,
        ffi.Pointer<bindings.IDENByteArray>)>(get1, false);

final putCB = ffi.Pointer.fromFunction<
    ffi.Bool Function(ffi.Pointer<ffi.Void>, bindings.IDENByteArray,
        bindings.IDENByteArray)>(put, false);

final getRootCB = ffi.Pointer.fromFunction<
    ffi.Bool Function(ffi.Pointer<ffi.Void> , ffi.Pointer<bindings.IDENByteArray>)>(getRoot, false);

final setRootCB = ffi.Pointer.fromFunction<
    ffi.Bool Function(ffi.Pointer<ffi.Void> , bindings.IDENByteArray)>(setRoot, false);

bindings.IDENMerkleTreeHash hashFromHex(String hex) {
  ffi.Pointer<bindings.IDENMerkleTreeHash> hash =
      ffi2.calloc<bindings.IDENMerkleTreeHash>();
  final ok = iden3lib.IDENHashFromHex(hash,
      hex.toNativeUtf8().cast<bindings.cchar_t>(), ffi.nullptr);
  assert(ok == 1);
  return hash.ref;
}

String hashToHex(bindings.IDENMerkleTreeHash h) {
  final root2 = Uint8List(32);
  for (int i = 0; i < 32; i++) {
    root2[i] = h.data[i];
  }
  return convert.hex.encode(root2);
}

String stringFromByteArray(bindings.IDENByteArray v) {
  if (v.data_len == 0) {
    return "";
  }

  final l = v.data.cast<ffi.Uint8>().asTypedList(v.data_len);
  final h = convert.hex.encode(l);
  return h;
}

void main (List<String> arguments) async {
  db = await sembast_io.databaseFactoryIo.openDatabase(dbPath);

  ffi.Pointer<ffi.Pointer<bindings.IDENStatus>> status =
    ffi2.malloc<ffi.Pointer<bindings.IDENStatus>>();
  ffi.Pointer<ffi.Pointer<bindings.IDENMerkleTree>> merkleTree =
    ffi2.malloc<ffi.Pointer<bindings.IDENMerkleTree>>();

  ffi.Pointer<bindings.IDENMtStorage> storage =
    ffi2.calloc<bindings.IDENMtStorage>();
  storage.ref.ctx = ffi.nullptr;
  storage.ref.get1 = get1CB;
  storage.ref.put = putCB;
  storage.ref.get_root = getRootCB;
  storage.ref.set_root = setRootCB;

  var ok = iden3lib.IDENNewMerkleTreeWithStorage(merkleTree, 40, storage, status);
  assert(ok == 1);

  final rndHashes = [
    "5fb90badb37c5821b6d95526a41a9504680b4e7c8b763a1b1d49d4955c848621",
    "65f606f6a63b7f3dfd2567c18979e4d60f26686d9bf2fb26c901ff354cde1607",
    "35d6042c4160f38ee9e2a9f3fb4ffb0019b454d522b5ffa17604193fb8966710",
    "ba53af19779cb2948b6570ffa0b773963c130ad797ddeafe4e3ad29b5125210f",
    "f4b6f44090a32711f3208e4e4b89cb5165ce64002cbd9c2887aa113df2468928",
    "8ced323cb76f0d3fac476c9fb03fc9228fbae88fd580663a0454b68312207f0a",
    "5a27db029de37ae37a42318813487685929359ca8c5eb94e152dc1af42ea3d16",
    "e50be1a6dc1d5768e8537988fddce562e9b948c918bba3e933e5c400cde5e60c",
    "0a8691332088a805bd55c446e25eb07590bafcccbec6177536401d9a2b7f512b",
    "54bfc9d00532adf5aaa7c3a96bc59b489f77d9042c5bce26b163defde5ee6a0f",
  ];

  for (int i = 0; i < rndHashes.length; i += 2) {
    final key = hashFromHex(rndHashes[i]);
    final value = hashFromHex(rndHashes[i+1]);
    ok = iden3lib.IDENMerkleTreeAddKeyValue(merkleTree.value, key, value, ffi.nullptr);
    assert(ok == 1);
  }

  ffi.Pointer<bindings.IDENMerkleTreeHash> root = ffi2.calloc<bindings.IDENMerkleTreeHash>();
  ok = iden3lib.IDENMerkleTreeRoot(root, merkleTree.value, ffi.nullptr);
  assert(ok == 1);

  final rootHex = hashToHex(root.ref);
  print('root: $rootHex');

  final wantRoot = 'f328105f00c03ff383006486b809ea8e2c03e47efe3681999bbdeadc8413de2d';
  assert(wantRoot == rootHex);

  await db?.close();
}
