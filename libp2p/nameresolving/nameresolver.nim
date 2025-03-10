# Nim-LibP2P
# Copyright (c) 2022 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import std/[sugar, sets, sequtils, strutils]
import
  chronos,
  chronicles,
  stew/[endians2, byteutils]
import ".."/[multiaddress, multicodec]

logScope:
  topics = "libp2p nameresolver"

type
  NameResolver* = ref object of RootObj

method resolveTxt*(
  self: NameResolver,
  address: string): Future[seq[string]] {.async, base.} =
  ## Get TXT record
  ##

  doAssert(false, "Not implemented!")

method resolveIp*(
  self: NameResolver,
  address: string,
  port: Port,
  domain: Domain = Domain.AF_UNSPEC): Future[seq[TransportAddress]] {.async, base.} =
  ## Resolve the specified address
  ##

  doAssert(false, "Not implemented!")

proc getHostname*(ma: MultiAddress): string =
  let
    firstPart = ma[0].valueOr: return ""
    fpSplitted = ($firstPart).split('/', 2)
  if fpSplitted.len > 2: fpSplitted[2]
  else: ""

proc resolveOneAddress(
  self: NameResolver,
  ma: MultiAddress,
  domain: Domain = Domain.AF_UNSPEC,
  prefix = ""): Future[seq[MultiAddress]]
  {.async, raises: [Defect, MaError, TransportAddressError].} =
  #Resolve a single address
  var pbuf: array[2, byte]

  var dnsval = getHostname(ma)

  if ma[1].tryGet().protoArgument(pbuf).tryGet() == 0:
    raise newException(MaError, "Incorrect port number")
  let
    port = Port(fromBytesBE(uint16, pbuf))
    resolvedAddresses = await self.resolveIp(prefix & dnsval, port, domain)

  return collect(newSeqOfCap(4)):
    for address in resolvedAddresses:
      var createdAddress = MultiAddress.init(address).tryGet()[0].tryGet()
      for part in ma:
        if DNS.match(part.tryGet()): continue
        createdAddress &= part.tryGet()
      createdAddress

proc resolveDnsAddr*(
  self: NameResolver,
  ma: MultiAddress,
  depth: int = 0): Future[seq[MultiAddress]] {.async.} =

  if not DNSADDR.matchPartial(ma):
    return @[ma]

  trace "Resolving dnsaddr", ma
  if depth > 6:
    info "Stopping DNSADDR recursion, probably malicious", ma
    return @[]

  var dnsval = getHostname(ma)

  let txt = await self.resolveTxt("_dnsaddr." & dnsval)

  trace "txt entries", txt

  var result: seq[MultiAddress]
  for entry in txt:
    if not entry.startsWith("dnsaddr="): continue
    let entryValue = MultiAddress.init(entry[8..^1]).tryGet()

    if entryValue.contains(multiCodec("p2p")).tryGet() and ma.contains(multiCodec("p2p")).tryGet():
      if entryValue[multiCodec("p2p")] != ma[multiCodec("p2p")]:
        continue

    let resolved = await self.resolveDnsAddr(entryValue, depth + 1)
    for r in resolved:
      result.add(r)

  if result.len == 0:
    debug "Failed to resolve a DNSADDR", ma
    return @[]
  return result


proc resolveMAddress*(
  self: NameResolver,
  address: MultiAddress): Future[seq[MultiAddress]] {.async.} =
  var res = initOrderedSet[MultiAddress]()

  if not DNS.matchPartial(address):
    res.incl(address)
  else:
    let code = address[0].get().protoCode().get()
    let seq = case code:
      of multiCodec("dns"):
        await self.resolveOneAddress(address)
      of multiCodec("dns4"):
        await self.resolveOneAddress(address, Domain.AF_INET)
      of multiCodec("dns6"):
        await self.resolveOneAddress(address, Domain.AF_INET6)
      of multiCodec("dnsaddr"):
        await self.resolveDnsAddr(address)
      else:
        doAssert false
        @[address]
    for ad in seq:
      res.incl(ad)
  return res.toSeq
