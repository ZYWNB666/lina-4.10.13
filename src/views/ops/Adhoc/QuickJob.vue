<template>
  <Page>
    <AdhocOpenDialog
      v-if="showOpenAdhocDialog"
      v-model:visible="showOpenAdhocDialog"
      @select="onSelectAdhoc"
    />
    <AdhocSaveDialog
      v-if="showOpenAdhocSaveDialog"
      v-model:visible="showOpenAdhocSaveDialog"
      :args="command"
      :module="module"
    />
    <VariableHelpDialog v-model:visible="showHelpDialog" />
    <SetVariableDialog
      v-model:visible="showSetVariableDialog"
      :form-data="variableFormData"
      :query-param="variableQueryParam"
      @submit="onSubmitVariable"
    />
    <ConfirmRunAssetsDialog
      v-model:visible="showConfirmRunAssetsDialog"
      :is-running="isRunning"
      :read-only="viewingExecution"
      :executed-assets="selectAssets"
      :assets="classifiedAssets"
      @submit="onConfirmRunAsset"
    />
    <div class="job-container">
      <div class="select-assets">
        <SelectJobAssetDialog @change="handleSelectAssets" />
      </div>
      <div class="transition-box">
        <CodeEditor v-if="ready" v-model="command" :options="cmOptions" :toolbar="toolbar" />
        <div class="xterm-container">
          <QuickJobTerm
            ref="xterm"
            :show-tool-bar="true"
            :select-assets="selectAssets"
            :xterm-config="xtermConfig"
            :execution-info="executionInfo"
            @view-assets="viewConfirmRunAssets"
          />
        </div>
      </div>
    </div>
  </Page>
</template>

<script>
import QuickJobTerm from '@/views/ops/Adhoc/components/QuickJobTerm.vue'
import CodeEditor from '@/components/Form/FormFields/CodeEditor'
import Page from '@/layout/components/Page'
import AdhocOpenDialog from './AdhocOpenDialog.vue'
import AdhocSaveDialog from './AdhocSaveDialog.vue'
import VariableHelpDialog from './VariableHelpDialog.vue'
import ConfirmRunAssetsDialog from './components/ConfirmRunAssetsDialog.vue'
import SetVariableDialog from '@/views/ops/Template/components/SetVariableDialog.vue'
import { createJob, getJob, getTaskDetail, stopJob } from '@/api/ops'
import { createWsUrl } from '@/utils/common/index'
import SelectJobAssetDialog from './components/SelectJobAssetDialog.vue'

export default {
  name: 'CommandExecution',
  components: {
    SelectJobAssetDialog,
    VariableHelpDialog,
    AdhocSaveDialog,
    AdhocOpenDialog,
    SetVariableDialog,
    Page,
    QuickJobTerm,
    CodeEditor,
    ConfirmRunAssetsDialog
  },
  data() {
    return {
      ready: true,
      currentStatus: '',
      currentTaskId: '',
      executionInfo: {
        status: '',
        summary: null,
        timeCost: 0,
        cancel: 0
      },
      xtermConfig: {},
      showHelpDialog: false,
      showOpenAdhocDialog: false,
      showOpenAdhocSaveDialog: false,
      showSetVariableDialog: false,
      showConfirmRunAssetsDialog: false,
      viewingExecution: false,
      runas: '',
      runasPolicy: 'skip',
      chdir: '',
      command: '',
      module: 'shell',
      timeout: -1,
      cmOptions: {
        mode: 'shell'
      },
      toolbar: {
        left: {
          run: {
            type: 'button',
            name: this.$t('Execute'),
            align: 'left',
            icon: 'fa fa-solid fa-play',
            tip: this.$t('RunCommand'),
            disabled: this.$store.getters.currentOrgIsRoot,
            el: {
              type: 'primary'
            },
            callback: () => {
              if (this.variableFormData.length !== 0) {
                this.showSetVariableDialog = true
                return
              }
              this.execute()
            }
          },
          stop: {
            type: 'button',
            name: this.$t('Stop'),
            align: 'left',
            icon: 'fa fa-solid fa-stop',
            tip: this.$t('StopJob'),
            isVisible: true,
            el: {
              type: 'danger'
            },
            callback: () => {
              this.stop()
            }
          },
          runas: {
            type: 'input',
            name: this.$t('RunAs'),
            align: 'left',
            value: '',
            placeholder: this.$tc('EnterRunUser'),
            tip: this.$tc('RunasHelpText'),
            el: {
              autoComplete: true,
              query: (query, cb) => {
                const { hosts, nodes } = this.getSelectedNodesAndHosts()

                if (hosts.length === 0 && nodes.length === 0) {
                  this.$message.warning(`${this.$t('RequiredAssetOrNode')}`)
                  return cb([])
                }
                cb([]) // 先返回空，避免输入时出现下拉闪烁
                this.$axios
                  .post('/api/v1/ops/username-hints/', {
                    nodes: nodes,
                    assets: hosts,
                    query: query
                  })
                  .then((data) => {
                    const ns = data.map((item) => {
                      return { value: item.username }
                    })
                    cb(ns)
                  })
              }
            },
            options: [],
            callback: (option) => {
              this.runas = option
            }
          },
          runasPolicy: {
            type: 'select',
            name: this.$t('RunasPolicy'),
            align: 'left',
            value: 'skip',
            tip: this.$tc('RunasPolicyHelpText'),
            options: [
              {
                label: this.$tc('Skip'),
                value: 'skip'
              },
              {
                label: this.$tc('PrivilegedFirst'),
                value: 'privileged_first'
              },
              {
                label: this.$tc('PrivilegedOnly'),
                value: 'privileged_only'
              }
            ],
            callback: (option) => {
              this.runasPolicy = option
            }
          },
          language: {
            type: 'select',
            name: this.$t('Module'),
            align: 'left',
            value: 'shell',
            options: [
              {
                label: 'Shell',
                value: 'shell'
              },
              {
                label: 'Powershell',
                value: 'win_shell'
              },
              {
                label: 'Raw',
                value: 'raw'
              },
              {
                label: 'Python',
                value: 'python'
              },
              {
                label: 'MySQL',
                value: 'mysql'
              },
              {
                label: 'PostgreSQL',
                value: 'postgresql'
              },
              {
                label: 'SQLServer',
                value: 'sqlserver'
              },
              {
                label: 'CloudEngine',
                value: 'huawei'
              }
            ],
            callback: (option) => {
              this.cmOptions.mode = option === 'win_shell' ? 'powershell' : option
              this.module = option
            }
          }
        },
        fold: {
          timeout: {
            type: 'select',
            name: this.$t('Timeout(s)'),
            align: 'left',
            value: 60,
            options: [
              { label: '10', value: 10 },
              { label: '30', value: 30 },
              { label: '60', value: 60 }
            ],
            callback: (option) => {
              this.timeout = option
            }
          },
          chdir: {
            type: 'input',
            name: this.$t('RunningPath'),
            align: 'left',
            value: '',
            placeholder: this.$tc('EnterRunningPath'),
            tip: this.$tc('RunningPathHelpText'),
            callback: (val) => {
              this.chdir = val
            }
          }
        },
        right: {
          openCommand: {
            type: 'button',
            align: 'right',
            icon: 'open',
            tip: this.$t('OpenCommand'),
            callback: (val, setting) => {
              this.showOpenAdhocDialog = true
            }
          },
          saveCommand: {
            type: 'button',
            align: 'right',
            icon: 'save',
            tip: this.$t('SaveCommand'),
            callback: (val, setting) => {
              if (!this.command) {
                return this.$message.error(this.$t('RequiredContent'))
              } else {
                this.showOpenAdhocSaveDialog = true
              }
            }
          },
          help: {
            type: 'button',
            align: 'right',
            icon: 'info',
            tip: this.$t('Help'),
            callback: (val, setting) => {
              this.showHelpDialog = true
            }
          }
        }
      },
      codeMirrorOptions: {
        lineNumbers: true,
        lineWrapping: true,
        mode: 'shell'
      },
      variableFormData: [],
      variableQueryParam: '',
      classifiedAssets: {
        error: [],
        runnable: [],
        skipped: []
      },
      selectAssets: [],
      selectNodes: [],
      selectHosts: [],
      targetNodes: [],
      isPreparing: false,
      isCreating: false
    }
  },
  computed: {
    xterm() {
      return this.$refs.xterm.xterm
    },
    isRunning() {
      return this.executionInfo.status?.value === 'running'
    }
  },
  watch: {
    command(iNew, iOld) {
      if (iNew === '') {
        this.variableFormData = []
      }
    }
  },
  mounted() {
    this.enableWS()
    this.initData()
  },
  beforeUnmount() {
    clearInterval(this.executionInfo.cancel)
    this.ws.onmessage = null
    this.ws.onerror = null
    this.ws.onopen = null
    this.ws.close()
  },
  methods: {
    async initData() {
      this.recoverStatus()
    },
    handleSelectAssets(assets, nodes = []) {
      this.selectHosts = assets
      this.targetNodes = nodes
    },
    recoverStatus() {
      if (this.$route.query.taskId) {
        this.currentTaskId = this.$route.query.taskId
        getTaskDetail(this.currentTaskId).then((data) => {
          getJob(data.job_id).then((res) => {
            this.toolbar.left.runas.value = res.runas
            this.toolbar.left.runas.callback(res.runas)
            this.toolbar.left.runasPolicy.value = res.runas_policy.value
            this.toolbar.left.runasPolicy.callback(res.runas_policy.value)
            this.toolbar.left.language.value = res.module.value
            this.toolbar.left.language.callback(res.module.value)
            this.toolbar.fold.timeout.value = res.timeout
            this.toolbar.fold.timeout.callback(res.timeout)
            this.command = res.args
            this.selectAssets = res.assets || []
            this.executionInfo.status = data['status']
            this.executionInfo.summary = data['summary']
            this.executionInfo.timeCost = data['time_cost']
            if (this.isRunning) this.setCostTimeInterval()
            this.setBtn()
            this.writeExecutionOutput()
          })
        })
      }
    },
    onSelectAdhoc(adhoc) {
      this.variableFormData = adhoc?.variable.map((data) => {
        return data.form_data
      })
      this.variableQueryParam = 'adhoc=' + adhoc.id
      this.command = adhoc.args
    },
    enableWS() {
      const wsURL = createWsUrl('/ws/ops/tasks/log/')
      this.ws = new WebSocket(wsURL)
      this.ws.onopen = () => {
        if (this.outputRequested) this.subscribeOutput()
      }
      this.ws.onerror = (e) => {
        this.xterm.write(this.wrapperError('Connect websocket server error'))
      }
      this.setWsCallback()
    },
    setWsCallback() {
      this.ws.onmessage = (e) => {
        const data = JSON.parse(e.data)
        if (Object.prototype.hasOwnProperty.call(data, 'message')) {
          let message = data.message
          message = message.replace(
            /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} Task ops\.tasks\.run_ops_job_execution.*/,
            ''
          )
          this.xterm.write(message)
        }
        if (Object.prototype.hasOwnProperty.call(data, 'event')) {
          const event = data.event
          switch (event) {
            case 'end':
              setTimeout(() => {
                this.getTaskStatus()
              }, 500)
              break
          }
        }
      }
    },
    getTaskStatus() {
      getTaskDetail(this.currentTaskId).then((data) => {
        this.executionInfo.status = data['status']
        this.executionInfo.summary = data['summary']
        this.setBtn()
      })
    },
    wrapperError(msg) {
      return `\r\n${msg}\r\n`
    },
    writeExecutionOutput() {
      this.outputRequested = true
      const msg = this.$t('CommandOutputWait')
      this.xterm.write(`${msg}\r\n`)
      if (this.ws.readyState === WebSocket.OPEN) this.subscribeOutput()
    },
    subscribeOutput() {
      if (this.subscribedTaskId === this.currentTaskId) return
      this.subscribedTaskId = this.currentTaskId
      this.ws.send(JSON.stringify({ task: this.currentTaskId }))
    },
    setCostTimeInterval() {
      clearInterval(this.executionInfo.cancel)
      this.toolbar.left.run.icon = 'fa fa-spinner fa-spin'
      this.toolbar.left.run.isVisible = true
      this.executionInfo.cancel = setInterval(() => {
        this.executionInfo.timeCost += 1
      }, 1000)
    },

    getSelectedNodesAndHosts() {
      return { hosts: [...this.selectHosts], nodes: [...this.targetNodes] }
    },
    execute() {
      if (this.isRunning || this.isPreparing || this.isCreating) return
      const { hosts, nodes } = this.getSelectedNodesAndHosts()
      if (hosts.length === 0 && nodes.length === 0) {
        this.$message.error(this.$tc('RequiredAssetOrNode'))
        return
      }
      if (this.command.length === 0) {
        this.$message.error(this.$tc('RequiredContent'))
        return
      }
      if (!this.runas) {
        this.$message.error(this.$tc('RequiredRunas'))
        return
      }
      const payload = {
        assets: hosts,
        nodes: nodes,
        module: this.module,
        args: this.command,
        runas: this.runas,
        runas_policy: this.runasPolicy
      }
      this.isPreparing = true
      this.toolbar.left.run.disabled = true
      return this.$axios
        .post('/api/v1/ops/classified-hosts/', {
          ...payload
        })
        .then((data) => {
          this.classifiedAssets = data
          this.viewingExecution = false
          if (
            this.classifiedAssets.runnable.length > 0 &&
            this.classifiedAssets.error.length === 0 &&
            nodes.length === 0
          ) {
            return this.onConfirmRunAsset(
              this.classifiedAssets.runnable.map((asset) => asset.id),
              []
            )
          } else {
            this.showConfirmRunAssetsDialog = true
          }
        })
        .catch((error) => this.$log.error(error))
        .finally(() => {
          this.isPreparing = false
          this.toolbar.left.run.disabled =
            this.isRunning || this.isCreating || this.$store.getters.currentOrgIsRoot
        })
    },
    onConfirmRunAsset(assets, nodes = []) {
      if (this.isRunning || this.isCreating || assets.length === 0) return
      this.isCreating = true
      this.toolbar.left.run.disabled = true
      const data = {
        assets: assets,
        nodes: nodes,
        module: this.module,
        args: this.command,
        runas: this.runas,
        runas_policy: this.runasPolicy,
        instant: true,
        is_periodic: false,
        timeout: this.timeout
      }
      if (this.chdir) {
        data.chdir = this.chdir
      }
      if (this.parameters) {
        data.parameters = this.parameters
      }
      return createJob(data)
        .then((res) => {
          this.xterm.reset()
          this.executionInfo.timeCost = 0
          this.executionInfo.summary = null
          this.executionInfo.status = { value: 'running', label: this.$t('Running') }
          this.currentTaskId = res.task_id
          this.xtermConfig = { taskId: this.currentTaskId, type: 'shortcut_cmd' }
          this.setCostTimeInterval()
          this.writeExecutionOutput()
          this.setBtn()
          this.selectAssets = assets
          this.selectNodes = nodes
        })
        .catch((error) => this.$log.error(error))
        .finally(() => {
          this.isCreating = false
          this.toolbar.left.run.disabled =
            this.isRunning || this.isCreating || this.$store.getters.currentOrgIsRoot
        })
    },
    viewConfirmRunAssets() {
      this.viewingExecution = true
      this.showConfirmRunAssetsDialog = true
    },
    stop() {
      stopJob({ task_id: this.currentTaskId })
        .then(() => {
          this.xterm.write(
            '\x1b[31m' +
              this.$tc('StopLogOutput').replace('currentTaskId', this.currentTaskId) +
              '\x1b[0m'
          )
          this.xterm.write(this.wrapperError(''))
          this.getTaskStatus()
        })
        .catch((e) => {
          this.$log.error(e)
        })
        .finally(() => {
          this.setBtn()
        })
    },
    setBtn() {
      if (!this.isRunning) {
        clearInterval(this.executionInfo.cancel)
        this.toolbar.left.run.icon = 'fa fa-solid fa-play'
      }
      this.toolbar.left.run.isVisible = this.isRunning
      this.toolbar.left.run.disabled =
        this.isRunning || this.isCreating || this.$store.getters.currentOrgIsRoot
      this.toolbar.left.stop.isVisible = !this.isRunning
    },
    onSubmitVariable(parameters) {
      this.parameters = parameters
      this.showSetVariableDialog = false
      this.execute()
    }
  }
}
</script>

<style lang="scss" scoped>
.job-container {
  display: flex;
  flex: 1;
  min-height: 0;
  gap: 20px;

  .select-assets {
    flex: 0 0 280px;
    min-width: 240px;
  }

  .transition-box {
    display: flex;
    flex: 1;
    flex-direction: column;
    min-width: 0;
    min-height: 0;
    gap: 20px;

    // 编辑器区套一层白色面板，避免直接露出内容区灰底（AppMain #f3f3f4）
    :deep(.code-editor) {
      box-sizing: border-box;
      padding: 14px 16px;
      background: #fff;
      border: 1px solid var(--color-border);
      border-radius: 8px;
    }

    .xterm-container {
      flex: 1;
      min-height: 240px;
      overflow: hidden;
      border: 1px solid var(--color-border);
      border-radius: 8px;

      & > div {
        height: 100%;
      }
    }
  }
}
@media (max-width: 1100px) {
  .job-container {
    flex-direction: column;
  }
  .job-container .select-assets {
    flex: 0 0 auto;
    max-height: 260px;
  }
  .job-container .transition-box {
    flex: 0 0 auto;
  }
  .job-container .transition-box .xterm-container {
    min-height: 320px;
    height: 360px;
    flex: none;
  }
}
</style>
