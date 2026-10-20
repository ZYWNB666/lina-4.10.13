<template>
  <Dialog
    :title="$t('ConfirmRunningAssets')"
    :visible="visible"
    :show-buttons="!isRunning"
    :show-confirm="selectedAssets.length > 0 && !readOnly"
    :show-cancel="true"
    width="1200px"
    @update:visible="$emit('update:visible', $event)"
    @confirm="onConfirm"
    @cancel="onCancel"
  >
    <div class="confirm-run-assets-dialog">
      <div class="runnable-assets">
        <div class="asset-group">
          <div class="group-title">
            {{ $t('RunnableAssets') }}
          </div>
          <el-checkbox
            :disabled="readOnly || isRunning"
            :indeterminate="isIndeterminate"
            :model-value="checkAll"
            style="padding-bottom: 5px"
            @change="handleCheckAllChange"
            @update:model-value="checkAll = $event"
          >
            {{ $t('All') }}
          </el-checkbox>
          <el-checkbox-group
            :disabled="readOnly || isRunning"
            :model-value="selectedAssets"
            class="group-assets"
            @change="handleCheckedAssetChange"
            @update:model-value="selectedAssets = $event"
          >
            <el-checkbox
              v-for="asset in runnableAssets"
              :key="asset.id"
              :value="asset.id"
              class="asset-item"
            >
              <div class="asset-item">
                <span
                  >{{ asset.name }}<span v-if="asset.ip">({{ asset.ip }})</span></span
                >
              </div>
            </el-checkbox>
          </el-checkbox-group>
        </div>
      </div>
      <div class="error-assets">
        <div class="group-title">{{ $t('NonRunnableAssets') }}</div>
        <div class="group-assets">
          <div v-for="asset in failedAssets" :key="asset.id" class="asset-item">
            <span><i class="fa fa-times-circle icon" />{{ asset.name }}</span>
            <span class="asset-status">{{ asset.error }}</span>
          </div>
        </div>
      </div>
    </div>
    <div>
      <div class="selected-count">{{ selectedAssets.length }}{{ $t('AssetsSelected') }}</div>
    </div>
  </Dialog>
</template>

<script>
import Dialog from '@/components/Dialog'

export default {
  name: 'ConfirmRunAssetsDialog',
  components: {
    Dialog
  },
  props: {
    readOnly: Boolean,
    executedAssets: { type: Array, default: () => [] },
    visible: {
      type: Boolean,
      default: false
    },
    assets: {
      type: Object,
      default: () => {}
    },
    isRunning: {
      type: Boolean,
      default: false
    }
  },
  emits: ['update:visible', 'submit'],
  data() {
    return {
      checkAll: true,
      selectedAssets: [],
      isIndeterminate: true
    }
  },
  computed: {
    runnableAssets() {
      return this.assets.runnable
    },
    failedAssets() {
      return this.assets.error
    }
  },
  watch: {
    visible(val) {
      if (val === true) {
        // 每次确认使用本次权限检查展开后的资产清单。
        this.selectedAssets = this.readOnly
          ? [...this.executedAssets]
          : this.runnableAssets.map((item) => item.id)
      }
    },
    runnableAssets(val) {
      // 去掉 selectedAssets 中不存在的 id
      this.selectedAssets = this.selectedAssets.filter((item) => {
        return val.some((asset) => asset.id === item)
      })
    }
  },
  methods: {
    onCancel() {
      this.$emit('update:visible', false)
    },
    onConfirm() {
      if (this.readOnly || this.isRunning || this.selectedAssets.length === 0) return
      this.$emit('submit', this.selectedAssets, [])
      this.$emit('update:visible', false)
    },
    handleCheckAllChange(value) {
      this.selectedAssets = value ? this.runnableAssets.map((item) => item.id) : []
      this.isIndeterminate = false
    },
    handleCheckedAssetChange(value) {
      const checkedCount = value.length
      this.checkAll = checkedCount === this.runnableAssets.length
      this.isIndeterminate = checkedCount > 0 && checkedCount < this.runnableAssets.length
    }
  }
}
</script>

<style scoped lang="scss">
.confirm-run-assets-dialog {
  .runnable-assets {
    padding-right: 10px;
  }

  display: grid;
  grid-template-columns: 1fr 1fr;
  grid-column-gap: 10px;

  .group-title {
    font-weight: bold;
    margin-bottom: 8px;
    font-size: 15px;
    background: #fbfbfd;
    padding: 10px;
  }

  .group-assets {
    :deep(.el-checkbox__label) {
      display: inline-block;
      padding-left: 10px;
      line-height: 19px;
      font-size: 13px;
      width: 100%;
    }

    max-height: 300px;
    overflow-y: auto;
    scrollbar-width: none;
    display: grid;
    grid-template-columns: 1fr;
    grid-row-gap: 5px;
    justify-items: start;

    .asset-item {
      display: flex;
      grid-template-columns: 1fr 1fr;
      justify-content: space-between;
      width: 100%;
      border-bottom: 1px solid #eee;

      .icon {
        color: #ed5565;
        padding-right: 3px;
      }

      .asset-ip {
        padding-right: 10px;
      }

      .asset-status {
        padding-right: 10px;
        color: #ed5565;
      }
    }
  }

  .group-assets::-webkit-scrollbar {
    display: none;
  }

  .footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-top: 16px;
  }

  .selected-count {
    color: #1ab394;
  }
}
</style>
