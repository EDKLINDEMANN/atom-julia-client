juno = require '../lib/julia-client'

# Testing-specific settings
juno.misc.paths.jlpath = -> "julia"

if process.platform is 'darwin'
  process.env.PATH += ':/usr/local/bin'

client = juno.connection.client

client.onStdout (s) -> console.log s
client.onStderr (s) -> console.log s

describe "the package", ->
  it "activates without errors", ->
    waitsForPromise ->
      atom.packages.activatePackage 'ink'
    waitsForPromise ->
      atom.packages.activatePackage 'julia-client'

describe "managing the client", ->
  clientStatus = -> [client.isConnected(), client.isActive(), client.isWorking()]
  {echo, evalsimple} = client.import ['echo', 'evalsimple']
  client.onConnected (connectSpy = jasmine.createSpy 'connect')
  client.onDisconnected (disconnectSpy = jasmine.createSpy 'disconnect')

  describe "before booting", ->
    path = require 'path'
    checkPath = (p) -> juno.misc.paths.getVersion p

    it "can validate an existing julia binary", ->
      waitsFor (done) ->
        checkPath(path.join __dirname, '..', '..', 'julia', 'julia').then -> done()

    it "can invalidate a non-existant julia binary", ->
      waitsFor (done) ->
        checkPath(path.join(__dirname, "foobar")).catch -> done()

    it "can validate a julia command", ->
      waitsFor (done) ->
        checkPath("julia").then -> done()

    it "can invalidate a non-existant julia command", ->
      waitsFor (done) ->
        checkPath("nojulia").catch -> done()

  describe "when booting the client", ->
    bootPromise = null

    it "recognises the client's state before boot", ->
      expect(clientStatus()).toEqual [false, false, false]

    it "initiates the boot", ->
      bootPromise = juno.connection.boot()

    it "recognises the client's state during boot", ->
      expect(clientStatus()).toEqual [false, true, true]

    it "waits for the boot to complete", ->
      waitsFor 'client to boot', 60*1000, (done) ->
        bootPromise.then (pong) ->
          expect(pong).toBe('pong')
          done()

    it "recognises the client's state after boot", ->
      expect(clientStatus()).toEqual [true, true, false]

    it "emits a connection event", ->
      expect(connectSpy.calls.length).toBe(1)

  describe "while the client is active", ->

    it "can send and receive nested objects, strings and arrays", ->
      msg = {x: 1, y: [1,2,3], z: "foo"}
      waitsForPromise ->
        echo(msg).then (response) ->
          expect(response).toEqual(msg)

    it "can evaluate code and return the result", ->
      [1..10].forEach (x) ->
        waitsForPromise ->
          evalsimple("#{x}^2").then (result) ->
            expect(result).toBe(Math.pow(x, 2))

    it "can rpc into the frontend", ->
      client.handle 'test', (x) -> Math.pow(x, 2)
      [1..10].forEach (x) ->
        waitsForPromise ->
          evalsimple("@rpc test(#{x})").then (result) ->
            expect(result).toBe(Math.pow(x, 2))

    it "can retrieve promise values from the frontend", ->
      client.handle 'test', (x) ->
        Promise.resolve x
      waitsForPromise ->
        evalsimple("@rpc test(2)").then (x) ->
          expect(x).toBe(2)

    it "captures stdout", ->
      data = ''
      sub = client.onStdout (s) -> data += s
      waitsForPromise ->
        evalsimple('print("test")')
      runs ->
        expect(data).toBe('test')
        sub.dispose()

    it "captures stderr", ->
      data = ''
      sub = client.onStderr (s) -> data += s
      waitsForPromise ->
        evalsimple('print(STDERR, "test")')
      runs ->
        expect(data).toBe('test')
        sub.dispose()

    describe "when callbacks are pending", ->
      {cbs, workingSpy, doneSpy} = {}

      it "registers loading listeners", ->
        client.onWorking (workingSpy = jasmine.createSpy 'working')
        client.onDone (doneSpy = jasmine.createSpy 'done')

      it "enters loading state", ->
        cbs = (evalsimple("peakflops(1000)") for i in [1..5])
        expect(client.isWorking()).toBe(true)

      it "emits a working event", ->
        expect(workingSpy.calls.length).toBe(1)

      it "stops loading after they are done", ->
        cbs.forEach (cb) ->
          waitsForPromise ->
            cb
        runs ->
          expect(client.isWorking()).toBe(false)

      it "emits a done event", ->
        expect(doneSpy.calls.length).toBe(1)

    it "can handle a large number of concurrent callbacks", ->
      n = 1000
      cbs = (evalsimple("sleep(rand()); #{i}^2") for i in [0...n])
      t = new Date().getTime()
      [0...n].forEach (i) ->
        waitsForPromise ->
          cbs[i].then (result) -> expect(result).toBe(Math.pow(i, 2))
      runs ->
        expect(new Date().getTime() - t).toBeLessThan(1500)

  describe "when the process is shut down", ->

    it "rejects pending callbacks", ->
      waitsFor (done) ->
        evalsimple('exit()').catch -> done()

    it "resets the working state", ->
      expect(client.isWorking()).toBe(false)

    it "emits a disconnection event", ->
      expect(disconnectSpy.calls.length).toBe(1)

    it "recognises the client's state after exit", ->
      expect(clientStatus()).toEqual [false, false, false]
