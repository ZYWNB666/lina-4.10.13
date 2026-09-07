<template>
  <div class="app-container machine-apply">
    <el-row>
      <el-col :xs="24" :sm="20" :md="16" :lg="14" :xl="12" :offset="4">
        <el-card shadow="never" class="box-card">
          <div slot="header" class="card-header">
            <span class="card-title"><i class="fa fa-server card-icon" />{{ $t('MachineApply') }}</span>
            <div class="card-tip">{{ $t('MachineApplyTip') }}</div>
          </div>

          <el-form ref="applyForm" :model="form" label-width="90px" @submit.native.prevent>
            <el-form-item :label="$t('SelectMachines')" required>
              <el-input
                v-model="treeFilter" size="small" clearable
                :placeholder="$t('Search')" prefix-icon="el-icon-search"
                style="margin-bottom: 8px"
              />
              <div v-loading="treeLoading" class="machine-tree">
                <el-tree
                  v-if="treeData.length"
                  ref="machineTree"
                  :data="treeData"
                  :props="treeProps"
                  node-key="id"
                  show-checkbox
                  default-expand-all
                  :expand-on-click-node="false"
                  :filter-node-method="filterNode"
                  @check="onCheckChange"
                >
                  <span slot-scope="{ data }" class="tree-node">
                    <i :class="data.type === 'node' ? 'fa fa-folder' : 'fa fa-desktop'" class="tree-icon" />
                    <span class="tree-label">{{ data.label }}</span>
                    <span v-if="data.type === 'asset'" class="tree-addr">{{ data.address }}</span>
                  </span>
                </el-tree>
                <div v-else class="tree-empty">{{ $t('NoMachineFound') }}</div>
              </div>
              <div v-if="selectedText" class="selected-summary">
                <i class="el-icon-info" /> {{ selectedText }}
              </div>
            </el-form-item>

            <el-form-item :label="$t('UseDuration')" required>
              <el-radio-group v-model="form.duration">
                <el-radio-button label="7">7 {{ $tc('Day') }}</el-radio-button>
                <el-radio-button label="30">30 {{ $tc('Day') }}</el-radio-button>
                <el-radio-button label="90">90 {{ $tc('Day') }}</el-radio-button>
                <el-radio-button label="custom">{{ $t('CustomDuration') }}</el-radio-button>
              </el-radio-group>
              <el-date-picker
                v-if="form.duration === 'custom'"
                v-model="form.customDate"
                type="datetime"
                :placeholder="$t('CustomExpired')"
                style="margin-left: 12px; width: 220px"
              />
            </el-form-item>

            <el-form-item :label="$t('Comment')">
              <el-input
                v-model="form.comment" type="textarea" :rows="3"
                maxlength="1024" show-word-limit
              />
            </el-form-item>

            <el-form-item>
              <el-button type="primary" :loading="submitting" @click="onSubmit">
                {{ $t('Submit') }}
              </el-button>
            </el-form-item>
          </el-form>
        </el-card>
      </el-col>
    </el-row>

    <el-dialog
      :title="result.auto_approved ? $t('AutoApproved') : $t('ApplySubmitted')" :visible.sync="resultVisible"
      width="420px" :close-on-click-modal="false" :show-close="false"
    >
      <div class="result-body">
        <i class="fa fa-check-circle result-icon" :class="{ 'icon-auto': result.auto_approved }" />
        <div class="result-serial">{{ result.serial_num }}</div>
        <div class="result-tip">
          {{ result.auto_approved ? $t('AutoApprovedTip') : $t('ApplySubmittedTip') }}
        </div>
      </div>
      <div slot="footer">
        <el-button @click="onViewTickets">{{ $t('MyTickets') }}</el-button>
        <el-button type="primary" @click="onReset">{{ $t('ApplyAgain') }}</el-button>
      </div>
    </el-dialog>
  </div>
</template>

<script>
// fork 定制: 机器访问申请(树状勾选: 可单选机器或整个目录, 目录授权含未来新增机器)
export default {
  name: 'MachineApply',
  data() {
    return {
      form: {
        duration: '30',
        customDate: '',
        comment: ''
      },
      treeData: [],
      treeLoading: false,
      treeFilter: '',
      treeProps: {
        children: 'children',
        label: 'label'
      },
      assetCount: 0,
      nodeCount: 0,
      submitting: false,
      resultVisible: false,
      result: {
        serial_num: ''
      }
    }
  },
  computed: {
    selectedText() {
      if (this.assetCount === 0 && this.nodeCount === 0) {
        return ''
      }
      return this.$t('SelectedSummary')
        .replace('{assets}', this.assetCount)
        .replace('{nodes}', this.nodeCount)
    }
  },
  watch: {
    treeFilter(value) {
      this.$refs.machineTree.filter(value)
    }
  },
  mounted() {
    this.loadTree()
  },
  methods: {
    async loadTree() {
      this.treeLoading = true
      try {
        const data = await this.$axios.get('/api/v1/xpack/feishu-approval/apply/assets/', { disableFlashErrorMsg: true })
        this.treeData = data.tree || []
      } catch (e) {
        // 静默
      } finally {
        this.treeLoading = false
      }
    },
    filterNode(value, data) {
      if (!value) {
        return true
      }
      const v = value.toLowerCase()
      return (
        data.label.toLowerCase().includes(v) ||
        (data.address || '').toLowerCase().includes(v)
      )
    },
    onCheckChange() {
      this.$nextTick(() => {
        const checked = this.$refs.machineTree.getCheckedKeys()
        this.assetCount = checked.filter(k => k.startsWith('asset-')).length
        this.nodeCount = checked.filter(k => k.startsWith('node-')).length
      })
    },
    onSubmit() {
      const checked = this.$refs.machineTree ? this.$refs.machineTree.getCheckedKeys() : []
      const assetIds = checked.filter(k => k.startsWith('asset-')).map(k => k.slice(6))
      const nodeIds = checked.filter(k => k.startsWith('node-')).map(k => k.slice(5))
      if (assetIds.length === 0 && nodeIds.length === 0) {
        return this.$message.warning(this.$t('SelectMachines'))
      }
      const body = { asset_ids: assetIds, node_ids: nodeIds, comment: this.form.comment }
      if (this.form.duration === 'custom') {
        if (!this.form.customDate) {
          return this.$message.warning(this.$t('CustomExpired'))
        }
        body.date_expired = this.$moment(this.form.customDate).format('YYYY-MM-DD HH:mm:ss')
      } else {
        body.days = parseInt(this.form.duration)
      }
      this.submitting = true
      this.$axios.post(
        '/api/v1/xpack/feishu-approval/apply/', body, { disableFlashErrorMsg: true }
      ).then(data => {
        this.result = data
        this.resultVisible = true
      }).catch(error => {
        const resp = error.response
        const msg = resp ? (resp.data.error || Object.values(resp.data)[0]) : this.$t('ServerError')
        this.$message.error(typeof msg === 'string' ? msg : JSON.stringify(msg))
      }).finally(() => {
        this.submitting = false
      })
    },
    onReset() {
      this.form.duration = '30'
      this.form.customDate = ''
      this.form.comment = ''
      if (this.$refs.machineTree) {
        this.$refs.machineTree.setCheckedKeys([])
      }
      this.assetCount = 0
      this.nodeCount = 0
      this.resultVisible = false
    },
    onViewTickets() {
      this.$router.push({ name: 'MyTicketList' })
    }
  }
}
</script>

<style lang="scss" scoped>
.machine-apply {
  .card-title {
    font-size: 16px;
    font-weight: 600;

    .card-icon {
      margin-right: 8px;
      color: var(--color-primary, #165dff);
    }
  }

  .card-tip {
    margin-top: 6px;
    font-size: 12px;
    color: var(--color-text-secondary, #86909c);
    font-weight: 400;
  }

  .machine-tree {
    border: 1px solid var(--color-border, #e5e6eb);
    border-radius: 4px;
    max-height: 320px;
    overflow: auto;
    padding: 4px 0;

    .tree-empty {
      padding: 32px;
      text-align: center;
      color: var(--color-text-secondary, #86909c);
      font-size: 13px;
    }
  }

  .tree-node {
    display: flex;
    align-items: center;
    font-size: 13px;
    overflow: hidden;
    text-overflow: ellipsis;

    .tree-icon {
      margin-right: 6px;
      color: var(--color-text-secondary, #86909c);
    }

    .tree-addr {
      margin-left: 8px;
      font-size: 12px;
      color: var(--color-text-secondary, #86909c);
    }
  }

  .selected-summary {
    margin-top: 8px;
    font-size: 12px;
    color: var(--color-primary, #165dff);
    line-height: 1.6;
  }

  .result-body {
    text-align: center;
    padding: 12px 0;

    .result-icon {
      font-size: 48px;
      color: var(--color-success, #00b42a);

      &.icon-auto {
        color: var(--color-primary, #165dff);
      }
    }

    .result-serial {
      margin-top: 12px;
      font-size: 16px;
      font-weight: 600;
    }

    .result-tip {
      margin-top: 8px;
      font-size: 12px;
      color: var(--color-text-secondary, #86909c);
      line-height: 1.8;
    }
  }
}
</style>
