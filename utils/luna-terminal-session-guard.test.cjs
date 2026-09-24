const assert = require('node:assert/strict')
const { readFileSync } = require('node:fs')
const { join } = require('node:path')
const { test } = require('node:test')
const vm = require('node:vm')

const source = readFileSync(join(__dirname, 'luna-terminal-session-guard.js'), 'utf8')
const flush = () => new Promise(setImmediate)

function setup({ supported = true, fail = false, delayed = false } = {}) {
  const requests = []
  class NativeWebSocket extends EventTarget {
    static OPEN = 1
    constructor(url, protocols) {
      super()
      this.url = new URL(url).href
      this.protocols = protocols
    }
    close() {
      this.dispatchEvent(new Event('close'))
    }
  }
  const window = { WebSocket: NativeWebSocket }
  const locks = {
    request(name, options, callback) {
      if (fail) return Promise.reject(new Error('denied'))
      const request = { name, options, granted: false, released: false }
      requests.push(request)
      return new Promise((resolve, reject) => {
        const abort = () => {
          if (!request.granted) reject(Object.assign(new Error('aborted'), { name: 'AbortError' }))
        }
        options.signal.addEventListener('abort', abort, { once: true })
        request.grant = async () => {
          if (options.signal.aborted) return
          request.granted = true
          await callback({ name, mode: options.mode })
          request.released = true
          options.signal.removeEventListener('abort', abort)
          resolve()
        }
        if (!delayed) queueMicrotask(request.grant)
      })
    }
  }
  const context = vm.createContext({
    window,
    navigator: { locks: supported ? locks : undefined },
    AbortController,
    URL,
    console: { warn() {} }
  })
  vm.runInContext(source, context)
  return { window, requests, context, NativeWebSocket, status: window.__jmsTerminalSessionGuard }
}

test('overlapping terminal sockets retain shared protection until each closes', async () => {
  const env = setup()
  const first = new env.window.WebSocket('wss://example.com/koko/ws/terminal/?token=secret', [
    'JMS-KOKO'
  ])
  const second = new env.window.WebSocket('wss://example.com/koko/ws/terminal')
  await flush()
  assert.equal(env.status.activeSockets, 2)
  assert.equal(env.status.heldLocks, 2)
  assert.ok(env.requests.every((r) => r.options.mode === 'shared'))
  assert.ok(env.requests.every((r) => !r.name.includes('secret')))
  first.close()
  first.close()
  await flush()
  assert.equal(env.status.heldLocks, 1)
  assert.equal(env.status.activeSockets, 1)
  second.close()
  await flush()
  assert.equal(env.status.heldLocks, 0)
  assert.equal(env.status.activeSockets, 0)
  assert.ok(env.requests.every((r) => r.released))
})

test('close before acquisition cancels a queued request without leaking a lock', async () => {
  const env = setup({ delayed: true })
  const socket = new env.window.WebSocket('wss://example.com/koko/ws/terminal/')
  socket.close()
  await env.requests[0].grant()
  await flush()
  assert.equal(env.status.heldLocks, 0)
  assert.equal(env.status.activeSockets, 0)
  assert.equal(env.status.failures, 0)
})

test('unrelated websocket connections never hold a terminal lock', () => {
  const env = setup()
  new env.window.WebSocket('wss://example.com/ws/notifications/')
  new env.window.WebSocket('wss://example.com/koko/ws/terminal/other')
  assert.equal(env.requests.length, 0)
})

test('native URL conversion, protocols, static constants and subclassing survive', async () => {
  const env = setup()
  let conversions = 0
  class DerivedSocket extends env.window.WebSocket {}
  const protocols = ['JMS-KOKO']
  const socket = new DerivedSocket(
    {
      toString() {
        conversions++
        return 'wss://example.com/koko/ws/terminal/'
      }
    },
    protocols
  )
  assert.equal(conversions, 1)
  assert.equal(socket.protocols, protocols)
  assert.equal(env.window.WebSocket.OPEN, 1)
  assert.ok(socket instanceof env.NativeWebSocket)
  assert.ok(socket instanceof DerivedSocket)
  assert.throws(() => new env.window.WebSocket('invalid-url'))
  socket.close()
  await flush()
})

test('missing Web Locks leaves the native WebSocket constructor untouched', () => {
  const env = setup({ supported: false })
  assert.equal(env.window.WebSocket, env.NativeWebSocket)
  assert.equal(env.status.supported, false)
})

test('lock denial is observable and does not break the terminal connection', async () => {
  const env = setup({ fail: true })
  const socket = new env.window.WebSocket('wss://example.com/koko/ws/terminal/')
  await flush()
  assert.equal(env.status.failures, 1)
  assert.equal(env.status.heldLocks, 0)
  socket.close()
  assert.equal(env.status.activeSockets, 0)
})

test('reloading the script in the same document does not wrap twice', async () => {
  const env = setup()
  const constructor = env.window.WebSocket
  vm.runInContext(source, env.context)
  assert.equal(env.window.WebSocket, constructor)
  const socket = new env.window.WebSocket('wss://example.com/koko/ws/terminal/')
  await flush()
  assert.equal(env.requests.length, 1)
  socket.close()
})
