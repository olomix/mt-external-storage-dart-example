import 'dart:typed_data';

import 'package:drt1/merkletree.dart';

main() {
  final h1 = Hash.fromHex("5fb90badb37c5821b6d95526a41a9504680b4e7c8b763a1b1d49d4955c848621");
  final h2 = Hash.fromHex("5fb90badb37c5821b6d95526a41a9504680b4e7c8b763a1b1d49d4955c848621");
  print("hashes: ${h1.hashCode}, ${h2.hashCode}");
  final mt = MerkleTree(MemoryStorage(), 40);
  print(mt);
  mt.add(Hash.fromHex("5fb90badb37c5821b6d95526a41a9504680b4e7c8b763a1b1d49d4955c848621").toBigInt(),
      Hash.fromHex("65f606f6a63b7f3dfd2567c18979e4d60f26686d9bf2fb26c901ff354cde1607").toBigInt());
  mt.add(Hash.fromHex("35d6042c4160f38ee9e2a9f3fb4ffb0019b454d522b5ffa17604193fb8966710").toBigInt(),
      Hash.fromHex("ba53af19779cb2948b6570ffa0b773963c130ad797ddeafe4e3ad29b5125210f").toBigInt());
  mt.add(Hash.fromHex("f4b6f44090a32711f3208e4e4b89cb5165ce64002cbd9c2887aa113df2468928").toBigInt(),
      Hash.fromHex("8ced323cb76f0d3fac476c9fb03fc9228fbae88fd580663a0454b68312207f0a").toBigInt());
  mt.add(Hash.fromHex("5a27db029de37ae37a42318813487685929359ca8c5eb94e152dc1af42ea3d16").toBigInt(),
      Hash.fromHex("e50be1a6dc1d5768e8537988fddce562e9b948c918bba3e933e5c400cde5e60c").toBigInt());
  mt.add(Hash.fromHex("0a8691332088a805bd55c446e25eb07590bafcccbec6177536401d9a2b7f512b").toBigInt(),
      Hash.fromHex("54bfc9d00532adf5aaa7c3a96bc59b489f77d9042c5bce26b163defde5ee6a0f").toBigInt());
  print("root: ${mt.root.toString()}");

  // 1825176478077037769293771472710124375213862324255094961984214597764985002889
  // 891b8614bddf3934fa1f113d006b57d7cecfb64134ff778fb83b8c2f66030904
  final bi = BigInt.parse("1825176478077037769293771472710124375213862324255094961984214597764985002889");
  print(bi);

  final h = Hash.fromBigInt(bi);
  print("h: $h (${h.toBigInt()})");
  final hh = Hash.fromHex("891b8614bddf3934fa1f113d006b57d7cecfb64134ff778fb83b8c2f66030904");
  print("hh: ${hh.toBigInt()}");

  // 9488010000000000000000000000000000000000000000000000000000000000
  final h15Int = BigInt.from(100500);
  final h15 = Hash.fromBigInt(h15Int);
  print("h15: $h15 (${h15.toBigInt()})");

  final b1 = BigInt.parse("21888242871839275222246405745257275088548364400416034343698204186575808495616");
  final b2 = BigInt.parse("21888242871839275222246405745257275088548364400416034343698204186575808495615");
  final b3 = BigInt.parse("21888242871839275222246405745257275088548364400416034343698204186575808495614");
  final b4 = poseidonHashInts3(b1, b2, b3);
  print("b4 = ${b4.toRadixString(10)}");
}
