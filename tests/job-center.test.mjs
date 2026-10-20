import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { test } from 'node:test'
import { parse } from '@vue/compiler-sfc'

async function options(file, dependencies = {}) {
  const source = await readFile(new URL(`../src/${file}`, import.meta.url), 'utf8')
  const { descriptor } = parse(source)
  const script = descriptor.script.content
    .replace(/^import .*$/gm, '')
    .replace(/  components: \{[\s\S]*?\},\n/, '')
    .replace('export default', 'return')
  return new Function(...Object.keys(dependencies), script)(...Object.values(dependencies))
}

function instance(component, extra = {}) {
  const view = {
    $t: (key) => key,
    $tc: (key) => key,
    $store: { getters: { currentOrgIsRoot: false } },
    $log: { error() {} },
    $message: { error: assert.fail },
    ...extra
  }
  Object.assign(view, component.data?.call(view))
  for (const [key, method] of Object.entries(component.methods || {})) view[key] = method.bind(view)
  for (const [key, get] of Object.entries(component.computed || {})) {
    Object.defineProperty(view, key, { get: () => get.call(view) })
  }
  return view
}

const directoryOptions = await options('views/ops/Adhoc/components/JobNodeSelectDialog.vue', {
  createUserAuthorizationTreeDataSource: () => ({})
})
const directory = (id) => ({ name: id, meta: { type: 'node', data: { id } } })
const nodeId = '00000000-0000-0000-0000-000000000001'
const classified = { runnable: [{ id: 'asset-1' }, { id: 'asset-2' }], error: [] }

async function quickJob(dependencies = {}) {
  const calls = []
  const component = await options('views/ops/Adhoc/QuickJob.vue', {
    createJob: async (data) => {
      calls.push(data)
      return { task_id: 'task-1' }
    },
    ...dependencies
  })
  const view = instance(component, { $refs: { xterm: { xterm: { reset() {}, write() {} } } } })
  view.command = 'hostname'
  view.runas = 'root'
  view.setCostTimeInterval = () => {}
  view.writeExecutionOutput = () => {}
  return { view, calls }
}

test('directory selection uses resource IDs, excludes synthetic roots, and keeps cancel transactional', () => {
  const original = [{ id: nodeId, name: 'parent' }]
  const view = instance(directoryOptions, { value: original })
  assert.equal(view.isDirectory(directory('ROOT')), false)
  assert.equal(view.isDirectory(directory('favorite-root')), false)
  assert.equal(view.isDirectory(directory('ungrouped')), true)
  view.toggleDirectory(directory(nodeId), true)
  view.toggleDirectory(directory(nodeId), true)
  assert.equal(view.selected.length, 1)
  view.remove(nodeId)
  assert.equal(view.selected.length, 0)
  assert.equal(original.length, 1)
})

test('directories alone are classified before confirming the resolved asset snapshot', async () => {
  const { view, calls } = await quickJob()
  view.handleSelectAssets([], [nodeId])
  view.$axios = {
    post: async (url, data) => {
      assert.equal(url, '/api/v1/ops/classified-hosts/')
      assert.deepEqual(data.nodes, [nodeId])
      assert.deepEqual(data.assets, [])
      return classified
    }
  }
  await view.execute()
  assert.equal(view.showConfirmRunAssetsDialog, true)
  assert.equal(view.classifiedAssets, classified)
  assert.equal(calls.length, 0)
  await view.onConfirmRunAsset(['asset-2'])
  assert.deepEqual(calls[0].assets, ['asset-2'])
  assert.deepEqual(calls[0].nodes, [])
})

test('individual targets execute the runnable IDs and repeat classification on subsequent runs', async () => {
  const { view, calls } = await quickJob()
  view.handleSelectAssets(['requested-asset'])
  let checks = 0
  view.$axios = {
    post: async () => {
      checks++
      return classified
    }
  }
  await view.execute()
  assert.deepEqual(calls[0].assets, ['asset-1', 'asset-2'])
  view.executionInfo.status = { value: 'success' }
  await view.execute()
  assert.equal(checks, 2)
})

test('empty directory expansion and network failure cannot create a job', async () => {
  const { view, calls } = await quickJob()
  view.handleSelectAssets([], [nodeId])
  view.$axios = { post: async () => ({ runnable: [], error: [] }) }
  await view.execute()
  await view.onConfirmRunAsset([])
  assert.equal(calls.length, 0)
  view.$axios.post = async () => {
    throw new Error('network failure')
  }
  await view.execute()
  assert.equal(view.isPreparing, false)
  assert.equal(view.toolbar.left.run.disabled, false)
  assert.equal(calls.length, 0)
})

test('double confirmation while creation is pending does not create a second job', async () => {
  let resolve
  let creates = 0
  const { view } = await quickJob({
    createJob: () => {
      creates++
      return new Promise((done) => {
        resolve = done
      })
    }
  })
  const first = view.onConfirmRunAsset(['asset-1'])
  view.onConfirmRunAsset(['asset-1'])
  assert.equal(creates, 1)
  resolve({ task_id: 'task-1' })
  await first
  assert.equal(view.isCreating, false)
  assert.equal(view.isRunning, true)
  // CodeEditor hides buttons with isVisible set.
  assert.equal(view.toolbar.left.run.isVisible, true)
  assert.equal(view.toolbar.left.stop.isVisible, false)
})

test('removing a directory preserves individually selected assets', async () => {
  const component = await options('views/ops/Adhoc/components/SelectJobAssetDialog.vue')
  const emitted = []
  const view = instance(component, { value: [], $emit: (...args) => emitted.push(args) })
  view.handleConfirm(['asset-1'], [{ id: 'asset-1', name: 'host' }])
  view.handleDirectories([{ id: nodeId, name: 'Linux' }])
  assert.deepEqual(emitted.at(-1), ['change', ['asset-1'], [nodeId]])
  view.removeDirectory(nodeId)
  assert.deepEqual(emitted.at(-1), ['change', ['asset-1'], []])
})

test('every confirmation starts with the current runnable snapshot', async () => {
  const component = await options('views/ops/Adhoc/components/ConfirmRunAssetsDialog.vue')
  const view = instance(component, { assets: classified })
  view.selectedAssets = ['stale-asset']
  component.watch.visible.call(view, true)
  assert.deepEqual(view.selectedAssets, ['asset-1', 'asset-2'])
})

test('inspecting a completed execution cannot submit another job', async () => {
  const component = await options('views/ops/Adhoc/components/ConfirmRunAssetsDialog.vue')
  const view = instance(component, {
    assets: classified,
    readOnly: true,
    executedAssets: ['asset-2'],
    $emit: assert.fail
  })
  component.watch.visible.call(view, true)
  assert.deepEqual(view.selectedAssets, ['asset-2'])
  view.onConfirm()
})
