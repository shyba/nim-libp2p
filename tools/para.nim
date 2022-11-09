import os
import osproc
import streams

type
  Program = ref object
    process: Process
    cmd: string
    output: string

var programs: seq[Program]
var x = 0
while x < paramCount():
  programs.add Program(
    process: startProcess(paramStr(x + 1), options = {poEvalCommand, poStdErrToStdOut}),
    cmd: paramStr(x + 1)
  )
  inc x

var allFinished = false
while not allFinished:
  allFinished = true

  for program in programs:
    if program.process.running:
      allFinished = false

    while not program.process.outputStream.atEnd:
      program.output &= program.process.outputStream.readAll()

  sleep(100)

var res = 0
for program in programs:
  res = max(abs(waitForExit(program.process)), res)
  echo "<===============>"
  echo program.cmd
  echo "<===============>"
  echo program.output
  close(program.process)

quit res
