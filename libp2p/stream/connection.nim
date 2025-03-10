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

import std/[hashes, oids, strformat]
import stew/results
import chronicles, chronos, metrics
import lpstream,
       ../multiaddress,
       ../peerinfo,
       ../errors

export lpstream, peerinfo, errors, results

logScope:
  topics = "libp2p connection"

const
  ConnectionTrackerName* = "Connection"
  DefaultConnectionTimeout* = 5.minutes

type
  TimeoutHandler* = proc(): Future[void] {.gcsafe, raises: [Defect].}

  Connection* = ref object of LPStream
    activity*: bool                 # reset every time data is sent or received
    timeout*: Duration              # channel timeout if no activity
    timerTaskFut: Future[void]      # the current timer instance
    timeoutHandler*: TimeoutHandler # timeout handler
    peerId*: PeerId
    observedAddr*: Opt[MultiAddress]
    upgraded*: Future[void]
    protocol*: string               # protocol used by the connection, used as tag for metrics
    transportDir*: Direction        # The bottom level transport (generally the socket) direction
    when defined(libp2p_agents_metrics):
      shortAgent*: string

proc timeoutMonitor(s: Connection) {.async, gcsafe.}

proc isUpgraded*(s: Connection): bool =
  if not isNil(s.upgraded):
    return s.upgraded.finished

proc upgrade*(s: Connection, failed: ref CatchableError = nil) =
  if not isNil(s.upgraded):
    if not isNil(failed):
      s.upgraded.fail(failed)
      return

    s.upgraded.complete()

proc onUpgrade*(s: Connection) {.async.} =
  if not isNil(s.upgraded):
    await s.upgraded

func shortLog*(conn: Connection): string =
  try:
    if conn.isNil: "Connection(nil)"
    else: &"{shortLog(conn.peerId)}:{conn.oid}"
  except ValueError as exc:
    raiseAssert(exc.msg)

chronicles.formatIt(Connection): shortLog(it)

method initStream*(s: Connection) =
  if s.objName.len == 0:
    s.objName = ConnectionTrackerName

  procCall LPStream(s).initStream()

  doAssert(isNil(s.timerTaskFut))

  if isNil(s.upgraded):
    s.upgraded = newFuture[void]()

  if s.timeout > 0.millis:
    trace "Monitoring for timeout", s, timeout = s.timeout

    s.timerTaskFut = s.timeoutMonitor()
    if isNil(s.timeoutHandler):
      s.timeoutHandler = proc(): Future[void] =
        trace "Idle timeout expired, closing connection", s
        s.close()

method closeImpl*(s: Connection): Future[void] =
  # Cleanup timeout timer
  trace "Closing connection", s

  if not isNil(s.timerTaskFut) and not s.timerTaskFut.finished:
    s.timerTaskFut.cancel()
    s.timerTaskFut = nil

  if not isNil(s.upgraded) and not s.upgraded.finished:
    s.upgraded.cancel()
    s.upgraded = nil

  trace "Closed connection", s

  procCall LPStream(s).closeImpl()

func hash*(p: Connection): Hash =
  cast[pointer](p).hash

proc pollActivity(s: Connection): Future[bool] {.async.} =
  if s.closed and s.atEof:
    return false # Done, no more monitoring

  if s.activity:
    s.activity = false
    return true

  # Inactivity timeout happened, call timeout monitor

  trace "Connection timed out", s
  if not(isNil(s.timeoutHandler)):
    trace "Calling timeout handler", s

    try:
      await s.timeoutHandler()
    except CancelledError:
      # timeoutHandler is expected to be fast, but it's still possible that
      # cancellation will happen here - no need to warn about it - we do want to
      # stop the polling however
      debug "Timeout handler cancelled", s
    except CatchableError as exc: # Shouldn't happen
      warn "exception in timeout handler", s, exc = exc.msg

  return false

proc timeoutMonitor(s: Connection) {.async, gcsafe.} =
  ## monitor the channel for inactivity
  ##
  ## if the timeout was hit, it means that
  ## neither incoming nor outgoing activity
  ## has been detected and the channel will
  ## be reset
  ##

  while true:
    try: # Sleep at least once!
      await sleepAsync(s.timeout)
    except CancelledError:
      return

    if not await s.pollActivity():
      return

method getWrapped*(s: Connection): Connection {.base.} =
  doAssert(false, "not implemented!")

proc new*(C: type Connection,
           peerId: PeerId,
           dir: Direction,
           observedAddr: Opt[MultiAddress],
           timeout: Duration = DefaultConnectionTimeout,
           timeoutHandler: TimeoutHandler = nil): Connection =
  result = C(peerId: peerId,
             dir: dir,
             timeout: timeout,
             timeoutHandler: timeoutHandler,
             observedAddr: observedAddr)

  result.initStream()
