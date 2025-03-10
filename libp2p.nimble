mode = ScriptMode.Verbose

packageName   = "libp2p"
version       = "1.0.0"
author        = "Status Research & Development GmbH"
description   = "LibP2P implementation"
license       = "MIT"
skipDirs      = @["tests", "examples", "Nim", "tools", "scripts", "docs"]

requires "nim >= 1.2.0",
         "nimcrypto >= 0.4.1",
         "dnsclient >= 0.3.0 & < 0.4.0",
         "bearssl >= 0.1.4",
         "chronicles >= 0.10.2",
         "chronos >= 3.0.6",
         "metrics",
         "secp256k1",
         "stew#head",
         "websock",
         "unittest2 >= 0.0.5 & < 0.1.0"

proc runTest(filename: string, verify: bool = true, sign: bool = true,
             moreoptions: string = "") =
  var excstr = "nim c --skipParentCfg --opt:speed -d:debug -d:libp2p_agents_metrics -d:libp2p_protobuf_metrics -d:libp2p_network_protocols_metrics -d:libp2p_mplex_metrics "
  excstr.add(" -d:chronicles_sinks=textlines[stdout],json[dynamic] -d:chronicles_log_level=TRACE ")
  excstr.add(" -d:chronicles_runtime_filtering=TRUE ")
  excstr.add(" " & getEnv("NIMFLAGS") & " ")
  excstr.add(" --verbosity:0 --hints:off ")
  excstr.add(" -d:libp2p_pubsub_sign=" & $sign)
  excstr.add(" -d:libp2p_pubsub_verify=" & $verify)
  excstr.add(" " & moreoptions & " ")
  exec excstr & " -r " & " tests/" & filename
  rmFile "tests/" & filename.toExe

proc buildSample(filename: string, run = false, extraFlags = "") =
  var excstr = "nim c --opt:speed --threads:on -d:debug --verbosity:0 --hints:off -p:. " & extraFlags
  excstr.add(" examples/" & filename)
  exec excstr
  if run:
    exec "./examples/" & filename.toExe
  rmFile "examples/" & filename.toExe

proc tutorialToMd(filename: string) =
  let markdown = gorge "cat " & filename & " | nim c -r --verbosity:0 --hints:off tools/markdown_builder.nim "
  writeFile(filename.replace(".nim", ".md"), markdown)

task testnative, "Runs libp2p native tests":
  runTest("testnative")

task testdaemon, "Runs daemon tests":
  runTest("testdaemon")

task testinterop, "Runs interop tests":
  runTest("testinterop")

task testpubsub, "Runs pubsub tests":
  runTest("pubsub/testgossipinternal", sign = false, verify = false, moreoptions = "-d:pubsub_internal_testing")
  runTest("pubsub/testpubsub")
  runTest("pubsub/testpubsub", sign = false, verify = false)
  runTest("pubsub/testpubsub", sign = false, verify = false, moreoptions = "-d:libp2p_pubsub_anonymize=true")

task testpubsub_slim, "Runs pubsub tests":
  runTest("pubsub/testgossipinternal", sign = false, verify = false, moreoptions = "-d:pubsub_internal_testing")
  runTest("pubsub/testpubsub")

task testfilter, "Run PKI filter test":
  runTest("testpkifilter",
           moreoptions = "-d:libp2p_pki_schemes=\"secp256k1\"")
  runTest("testpkifilter",
           moreoptions = "-d:libp2p_pki_schemes=\"secp256k1;ed25519\"")
  runTest("testpkifilter",
           moreoptions = "-d:libp2p_pki_schemes=\"secp256k1;ed25519;ecnist\"")
  runTest("testpkifilter",
           moreoptions = "-d:libp2p_pki_schemes=")

task test, "Runs the test suite":
  exec "nimble testnative"
  exec "nimble testpubsub"
  exec "nimble testdaemon"
  exec "nimble testinterop"
  exec "nimble testfilter"
  exec "nimble examples_build"

task test_slim, "Runs the (slimmed down) test suite":
  exec "nimble testnative"
  exec "nimble testpubsub_slim"
  exec "nimble testfilter"
  exec "nimble examples_build"

task website, "Build the website":
  tutorialToMd("examples/tutorial_1_connect.nim")
  tutorialToMd("examples/tutorial_2_customproto.nim")
  tutorialToMd("examples/tutorial_3_protobuf.nim")
  tutorialToMd("examples/tutorial_4_gossipsub.nim")
  tutorialToMd("examples/tutorial_5_discovery.nim")
  tutorialToMd("examples/tutorial_6_game.nim")
  tutorialToMd("examples/circuitrelay.nim")
  exec "mkdocs build"

task examples_build, "Build the samples":
  buildSample("directchat")
  buildSample("helloworld", true)
  buildSample("circuitrelay", true)
  buildSample("tutorial_1_connect", true)
  buildSample("tutorial_2_customproto", true)
  if (NimMajor, NimMinor) > (1, 2):
    # These tutorials relies on post 1.4 exception tracking
    buildSample("tutorial_3_protobuf", true)
    buildSample("tutorial_4_gossipsub", true)
    buildSample("tutorial_5_discovery", true)
    # Nico doesn't work in 1.2
    exec "nimble install -y nimpng@#HEAD" # this is to fix broken build on 1.7.3, remove it when nimpng version 0.3.2 or later is released
    exec "nimble install -y nico"
    buildSample("tutorial_6_game", false, "--styleCheck:off")

# pin system
# while nimble lockfile
# isn't available

const PinFile = ".pinned"
task pin, "Create a lockfile":
  # pinner.nim was originally here
  # but you can't read output from
  # a command in a nimscript
  exec "nim c -r tools/pinner.nim"

import sequtils
import os
task install_pinned, "Reads the lockfile":
  let toInstall = readFile(PinFile).splitWhitespace().mapIt((it.split(";", 1)[0], it.split(";", 1)[1]))
  # [('packageName', 'packageFullUri')]

  rmDir("nimbledeps")
  mkDir("nimbledeps")
  exec "nimble install -y " & toInstall.mapIt(it[1]).join(" ")

  # Remove the automatically installed deps
  # (inefficient you say?)
  let allowedDirectories = toInstall.mapIt(it[0] & "-" & it[1].split('@')[1])
  for dependency in listDirs("nimbledeps/pkgs"):
    if dependency.extractFilename notin allowedDirectories:
      rmDir(dependency)

task unpin, "Restore global package use":
  rmDir("nimbledeps")
