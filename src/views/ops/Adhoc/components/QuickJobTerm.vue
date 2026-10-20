<template>
  <div class="term-wrapper">
    <div class="term-header">
      <div class="header-text">{{ $tc('Output') }}</div>
      <el-tag v-if="executionInfo.status" :type="statusType" effect="light" round>
        {{ $tc(executionInfo.status.label) }}
      </el-tag>
      <div v-if="showToolBar" class="actions">
        <div v-for="(item, index) in toolbar" :key="index" class="action-item">
          <el-tooltip :content="item.tip" :show-after="500">
            <el-button size="small" text :aria-label="item.tip" @click="item.callback()">
              <svg-icon :icon-class="item.icon" />
            </el-button>
          </el-tooltip>
        </div>
      </div>
    </div>
    <div v-if="executionInfo.status" class="execution-summary">
      <el-button link @click="viewConfirmRunAssets">{{
        $t('JobExecutionAssets', { count: selectAssets.length })
      }}</el-button>
      <span v-if="summary" class="status_success"
        >{{ $tc('Success') }} <strong>{{ summary.success }}</strong></span
      >
      <span v-if="summary" class="status_danger"
        >{{ $tc('Failed') }} <strong>{{ summary.failed }}</strong></span
      >
      <span v-if="executionInfo.summary?.unexecuted" class="status_warning">
        {{ $tc('NotExecuted') }} <strong>{{ executionInfo.summary.unexecuted }}</strong>
        <span v-if="executionInfo.summary.error_code === 'command_acl_rejected'"
          >({{ $tc('CommandRejectedByACL') }})</span
        >
      </span>
      <span class="execution-time"
        >{{ $tc('TimeDelta') }} <strong>{{ executionInfo.timeCost }}s</strong></span
      >
    </div>
    <div class="terminal-body">
      <div ref="terminal" class="xterm" />
      <div v-if="!executionInfo.status && !hasOutput" class="output-empty">
        <el-icon><Monitor /></el-icon>
        <span>{{ $t('JobOutputEmpty') }}</span>
        <small>{{ $t('JobOutputHelp') }}</small>
      </div>
    </div>
  </div>
</template>

<script>
import { markRaw } from 'vue'
import { downloadText } from '@/utils/common/index'
import { Terminal } from 'xterm'
import { FitAddon } from 'xterm-addon-fit'
import 'xterm/css/xterm.css'

export default {
  name: 'Term',
  props: {
    showToolBar: {
      type: [Boolean, Object],
      default: () => {
        return false
      }
    },
    xtermConfig: {
      type: Object,
      default: () => {}
    },
    executionInfo: {
      type: Object,
      // eslint-disable-next-line vue/require-valid-default-prop
      default: {}
    },
    selectAssets: {
      type: Array,
      default: () => []
    }
  },
  data() {
    return {
      xterm: markRaw(
        new Terminal(
          Object.assign(
            {
              fontFamily: 'monaco, Consolas, "Lucida Console", monospace',
              lineHeight: 1.5,
              disableStdin: true,
              cursorBlink: false,
              fontSize: 13,
              scrollback: 9999999,
              rightClickSelectsWord: true,
              theme: {
                background: '#141c2b',
                foreground: '#dbe4f0',
                selectionBackground: '#435676',
                selectionInactiveBackground: '#34435e',
                cursor: '#141c2b',
                black: '#263245',
                red: '#fb7185',
                green: '#6ee7b7',
                yellow: '#fcd34d',
                blue: '#7db5ff',
                magenta: '#c4b5fd',
                cyan: '#67e8f9',
                white: '#dbe4f0',
                brightBlack: '#94a3b8'
              }
            },
            this.xtermConfig
          )
        )
      ),
      toolbar: [
        {
          tip: this.$tc('ScrollToTop'),
          icon: 'arrow-up',
          callback: this.scrollToTop
        },
        {
          tip: this.$tc('ScrollToBottom'),
          icon: 'arrow-down',
          callback: this.scrollToBottom
        },
        {
          tip: this.$tc('ClearScreen'),
          icon: 'refresh',
          callback: () => {
            this.xterm.reset()
          }
        },
        {
          tip: this.$tc('Export'),
          icon: 'download',
          callback: () => {
            this.xterm.selectAll()
            const text = this.xterm.getSelection()
            const filename = `${this.xtermConfig?.type}_${this.xtermConfig?.taskId}.log`
            downloadText(text, filename)
          }
        }
      ],
      hasOutput: false
    }
  },
  computed: {
    statusType() {
      return (
        { success: 'success', failed: 'danger', timeout: 'warning', running: 'primary' }[
          this.executionInfo.status?.value
        ] || 'info'
      )
    },
    summary() {
      const { ok, failures = {}, dark = {} } = this.executionInfo.summary || {}
      if (!ok) return null
      return {
        success: ok.length,
        failed: Object.keys({ ...failures, ...dark }).length
      }
    }
  },
  mounted: function () {
    const terminalContainer = this.$refs.terminal
    const fitAddon = new FitAddon()
    this.xterm.loadAddon(fitAddon)
    this.xterm.open(terminalContainer)
    this.resizeObserver = new ResizeObserver(() => {
      if (terminalContainer.clientWidth && terminalContainer.clientHeight) fitAddon.fit()
    })
    this.resizeObserver.observe(terminalContainer)
    this.outputSubscription = this.xterm.onWriteParsed(() => {
      this.hasOutput = true
    })
    this.xterm.scrollToBottom()
  },
  beforeUnmount() {
    this.resizeObserver?.disconnect()
    this.outputSubscription?.dispose()
    this.xterm.dispose()
  },
  methods: {
    reset: function () {
      this.xterm.reset()
    },
    write: function (val) {
      this.xterm.write(val)
    },
    scrollToTop() {
      this.xterm.scrollToTop()
    },
    scrollToBottom() {
      this.xterm.scrollToBottom()
    },
    viewConfirmRunAssets() {
      this.$emit('view-assets')
    }
  }
}
</script>

<style scoped lang="scss">
.term-wrapper {
  display: flex;
  flex-direction: column;
  min-height: 0;
  background: var(--el-bg-color, #fff);
}
.term-header {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 12px;
  padding: 12px 16px;
  border-bottom: 1px solid var(--color-border);
  .header-text {
    font-size: 14px;
    font-weight: 600;
  }
  .actions {
    display: flex;
    margin-left: auto;
    gap: 4px;
  }
  .el-button {
    width: 28px;
    height: 28px;
    padding: 6px;
  }
}
.execution-summary {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 16px;
  padding: 10px 16px;
  font-size: 12px;
  color: var(--color-text-secondary);
  strong {
    margin-left: 4px;
    font-variant-numeric: tabular-nums;
  }
  .execution-time {
    margin-left: auto;
  }
  .status_success {
    color: var(--el-color-success);
  }
  .status_danger {
    color: var(--color-danger);
  }
  .status_warning {
    color: var(--color-warning);
  }
}
.terminal-body {
  position: relative;
  display: flex;
  flex: 1;
  min-height: 180px;
  background: #141c2b;
  padding: 16px;
}
.xterm {
  flex: 1;
  min-width: 0;
  min-height: 0;
  overflow: hidden;
}
.output-empty {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  pointer-events: none;
  color: #cbd5e1;
  .el-icon {
    font-size: 28px;
    color: #7db5ff;
  }
  small {
    color: #94a3b8;
  }
}
</style>
