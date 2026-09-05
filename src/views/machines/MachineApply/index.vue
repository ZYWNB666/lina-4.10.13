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
              <el-select
                v-model="form.assets"
                v-loading="assetsLoading"
                multiple filterable remote reserve-keyword
                :remote-method="searchAssets"
                :loading="assetsLoading"
                :placeholder="$t('Search')"
                style="width: 100%"
                @visible-change="onSelectVisible"
              >
                <el-option
                  v-for="a in assetOptions"
                  :key="a.id"
                  :label="`${a.name} (${a.address})`"
                  :value="a.id"
                >
                  <span style="float: left">{{ a.name }}</span>
                  <span class="asset-option-addr">{{ a.address }}</span>
                </el-option>
              </el-select>
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
      :title="$t('ApplySubmitted')" :visible.sync="resultVisible"
      width="420px" :close-on-click-modal="false" :show-close="false"
    >
      <div class="result-body">
        <i class="fa fa-check-circle result-icon" />
        <div class="result-serial">{{ result.serial_num }}</div>
        <div class="result-tip">{{ $t('ApplySubmittedTip') }}</div>
      </div>
      <div slot="footer">
        <el-button @click="onViewTickets">{{ $t('MyTickets') }}</el-button>
        <el-button type="primary" @click="onReset">{{ $t('ApplyAgain') }}</el-button>
      </div>
    </el-dialog>
  </div>
</template>

<script>
// fork 定制: 机器访问申请(极简表单, 提交到 feishu_approval 插件 API,
// 服务端强制 @USER 账号/动作, 审批通过后自动开通)
export default {
  name: 'MachineApply',
  data() {
    return {
      form: {
        assets: [],
        duration: '30',
        customDate: '',
        comment: ''
      },
      assetOptions: [],
      assetsLoading: false,
      submitting: false,
      resultVisible: false,
      result: {
        serial_num: ''
      }
    }
  },
  mounted() {
    this.searchAssets('')
  },
  methods: {
    async searchAssets(query) {
      this.assetsLoading = true
      try {
        const url = '/api/v1/xpack/feishu-approval/apply/assets/?search=' + encodeURIComponent(query || '')
        const data = await this.$axios.get(url, { disableFlashErrorMsg: true })
        this.assetOptions = data.results || []
      } catch (e) {
        // 静默, 下拉打开时会重试
      } finally {
        this.assetsLoading = false
      }
    },
    onSelectVisible(visible) {
      if (visible && this.assetOptions.length === 0) {
        this.searchAssets('')
      }
    },
    onSubmit() {
      if (this.form.assets.length === 0) {
        return this.$message.warning(this.$t('SelectMachines'))
      }
      const body = { asset_ids: this.form.assets, comment: this.form.comment }
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
      this.form.assets = []
      this.form.duration = '30'
      this.form.customDate = ''
      this.form.comment = ''
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
      color: var(--color-primary);
    }
  }

  .card-tip {
    margin-top: 6px;
    font-size: 12px;
    color: var(--color-text-secondary, #86909c);
    font-weight: 400;
  }

  .asset-option-addr {
    float: right;
    font-size: 12px;
    color: var(--color-text-secondary, #86909c);
  }

  .result-body {
    text-align: center;
    padding: 12px 0;

    .result-icon {
      font-size: 48px;
      color: var(--color-success, #00b42a);
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
