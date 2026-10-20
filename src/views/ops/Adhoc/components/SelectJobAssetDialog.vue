<template>
  <div class="asset-select">
    <IBox title="selectedAssets" class="asset-card">
      <template #header>
        <div class="asset-card-header">
          <span class="asset-card-title">{{ $t('JobTargets') }}</span>
        </div>
      </template>
      <div class="target-actions">
        <el-button @click="directoryDialogVisible = true"
          ><el-icon><Folder /></el-icon>{{ $t('JobSelectDirectories') }}</el-button
        >
        <el-button @click="handleClick"
          ><el-icon><Plus /></el-icon>{{ $t('Asset') }}</el-button
        >
      </div>
      <p class="target-summary">
        {{
          $t('JobTargetCount', {
            assets: selectAssets.length,
            directories: selectedDirectories.length
          })
        }}
      </p>
      <div v-if="selectedDirectories.length" class="directory-list">
        <div v-for="node in selectedDirectories" :key="node.id" class="directory-row">
          <el-icon><Folder /></el-icon>
          <span :title="node.name">{{ node.name }}</span>
          <el-button text :aria-label="$t('Remove')" @click="removeDirectory(node.id)"
            ><el-icon><Close /></el-icon
          ></el-button>
        </div>
        <p class="directory-hint">{{ $t('JobDirectoryHelp') }}</p>
      </div>
      <div
        v-if="selectAssetRows.length === 0 && selectedDirectories.length === 0"
        class="empty-assets"
        role="button"
        tabindex="0"
        :aria-label="$t('pleaseSelectAssets')"
        @click="handleClick()"
        @keydown.enter.prevent="handleClick()"
        @keydown.space.prevent="handleClick()"
      >
        <el-icon class="icon"><Plus /></el-icon>
        <span class="title">{{ $t('pleaseSelectAssets') }}</span>
        <span class="subtitle">{{ $t('clickToAdd') }}</span>
      </div>
      <div v-if="selectAssetRows.length" class="asset-list">
        <div v-for="group in groupedAssets" :key="group.key" class="platform-group">
          <div class="platform-group-header">
            <el-checkbox
              :indeterminate="isPlatformIndeterminate(group)"
              :model-value="isPlatformAllSelected(group)"
              @change="(val) => togglePlatformAll(group, val)"
            >
              <span class="platform-title">
                <img
                  v-if="group.assets.length"
                  :src="getPlatformLogo(group.assets[0])"
                  class="platform-icon"
                />
                {{ group.platformName }} ({{ group.assets.length }})
              </span>
            </el-checkbox>
          </div>
          <el-checkbox-group
            v-model="selectAssets"
            class="platform-group-assets"
            @change="onCheckboxChange"
          >
            <el-checkbox v-for="item in group.assets" :key="item.id" :value="item.id">
              <span :title="item.name" class="asset-name">{{ item.name }}</span>
              <el-icon
                class="asset-remove-icon"
                :title="$tc('Remove')"
                @click.stop="removeAsset(item)"
                ><Minus
              /></el-icon>
            </el-checkbox>
          </el-checkbox-group>
        </div>
      </div>
    </IBox>
    <JobNodeSelectDialog
      v-if="directoryDialogVisible"
      v-model:visible="directoryDialogVisible"
      :value="selectedDirectories"
      @confirm="handleDirectories"
    />

    <UserAssetSelectDialog
      v-if="dialogVisible"
      v-model:visible="dialogVisible"
      :base-url="baseUrl"
      :page-size="defaultPageSize"
      settings-cache-key="job-asset-select-dialog"
      :title="dialogTitle"
      :value="selectAssets"
      @cancel="handleCancel"
      @confirm="handleConfirm"
    />
  </div>
</template>

<script>
import UserAssetSelectDialog from '@/components/Apps/GrantedAssets/UserAssetSelectDialog.vue'
import IBox from '@/components/Common/IBox/index.vue'
import JobNodeSelectDialog from './JobNodeSelectDialog.vue'
import { loadPlatformIcon } from '@/utils/jms/index'

export default {
  componentName: 'SelectJobAssetDialog',
  components: { UserAssetSelectDialog, IBox, JobNodeSelectDialog },
  emits: ['change'],
  props: {
    baseUrl: {
      type: String,
      default: '/api/v1/perms/users/self/assets/'
    },
    defaultPageSize: {
      type: Number,
      default: 10
    },
    dialogTitle: {
      type: String,
      default: ''
    },
    value: {
      type: Array,
      default: () => []
    }
  },
  data() {
    return {
      dialogVisible: false,
      directoryDialogVisible: false,
      selectedDirectories: [],
      selectAssetRows: [],
      selectAssets: [...this.value]
    }
  },
  computed: {
    groupedAssets() {
      const map = {}
      this.selectAssetRows.forEach((a) => {
        const key = a?.type?.value || 'unknown'
        const name = a?.type?.label || a?.type?.value || 'Unknown'
        if (!map[key]) {
          map[key] = { key, platformName: name, assets: [] }
        }
        map[key].assets.push(a)
      })
      return Object.values(map)
        .map((g) => {
          g.assets = g.assets.slice().sort((x, y) => (x.name || '').localeCompare(y.name || ''))
          return g
        })
        .sort((a, b) => a.platformName.localeCompare(b.platformName))
    }
  },
  methods: {
    emitSelection() {
      this.$emit(
        'change',
        [...this.selectAssets],
        this.selectedDirectories.map((node) => node.id)
      )
    },
    handleDirectories(nodes) {
      this.selectedDirectories = nodes
      this.emitSelection()
    },
    removeDirectory(id) {
      this.selectedDirectories = this.selectedDirectories.filter((node) => node.id !== id)
      this.emitSelection()
    },
    handleClick() {
      this.dialogVisible = true
    },
    handleConfirm(valueSelected, rowsAdd) {
      if (valueSelected === undefined) {
        return
      }
      rowsAdd.forEach((item) => {
        if (!this.selectAssetRows.find((i) => i.id === item.id)) {
          this.selectAssetRows.push(item)
        }
      })
      // 移除已经取消选择的资产
      this.selectAssetRows = this.selectAssetRows.filter((r) => valueSelected.includes(r.id))
      this.selectAssets = valueSelected
      this.emitSelection()
      this.dialogVisible = false
    },
    handleCancel() {
      this.dialogVisible = false
    },
    getPlatformLogo(platform) {
      return loadPlatformIcon(platform.name, platform.type.value)
    },
    onCheckboxChange(value) {
      this.selectAssets = value
      this.emitSelection()
    },
    isPlatformAllSelected(group) {
      return group.assets.length > 0 && group.assets.every((a) => this.selectAssets.includes(a.id))
    },
    isPlatformIndeterminate(group) {
      const selected = group.assets.filter((a) => this.selectAssets.includes(a.id)).length
      return selected > 0 && selected < group.assets.length
    },
    togglePlatformAll(group, checked) {
      const ids = group.assets.map((a) => a.id)
      if (checked) {
        const merged = new Set(this.selectAssets.concat(ids))
        this.selectAssets = Array.from(merged)
      } else {
        this.selectAssets = this.selectAssets.filter((id) => !ids.includes(id))
      }
      this.emitSelection()
    },
    removeAsset(asset) {
      this.selectAssets = this.selectAssets.filter((id) => id !== asset.id)
      this.selectAssetRows = this.selectAssetRows.filter((r) => r.id !== asset.id)
      this.emitSelection()
    }
  }
}
</script>

<style lang="scss" scoped>
.target-actions {
  display: flex;
  gap: 8px;
  .el-button {
    flex: 1;
    margin: 0;
    .el-icon {
      margin-right: 5px;
    }
  }
}
.target-summary,
.directory-hint {
  font-size: 12px;
  color: var(--color-text-secondary);
}
.directory-list {
  margin-bottom: 12px;
  padding-bottom: 12px;
  border-bottom: 1px solid var(--color-border);
}
.directory-row {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 5px 8px;
  border-radius: 5px;
  background: var(--el-fill-color-light);
  margin-bottom: 6px;
  > span {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .el-button {
    padding: 4px;
  }
}
.directory-hint {
  margin: 8px 0 0;
  line-height: 1.6;
}
.asset-select {
  display: flex;
  flex-direction: column;
  height: 100%;
  color: var(--color-text-primary);

  .asset-card {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;

    // 卡片体撑满剩余高度并内部滚动，替代固定的 calc(100vh - 200px)
    :deep(.el-card__body) {
      flex: 1;
      min-height: 0;
      padding: 10px 16px;
      overflow-y: auto;
      overflow-x: hidden;
    }

    :deep(.el-checkbox) {
      width: 100%;
      display: flex;
      padding: 3px 0;
      margin-right: 0;
      align-items: center;

      .asset-remove-icon {
        opacity: 0;
        visibility: hidden;
        cursor: pointer;
        font-weight: normal;
        transition: opacity 0.15s ease;
        margin-left: auto;
        color: var(--color-danger);
      }

      .el-checkbox__label {
        width: 100%;
        display: flex;
        align-items: center;
        gap: 3px;
        padding-right: 20px;
        padding-left: 3px;
      }

      .el-checkbox__label:hover .asset-remove-icon {
        opacity: 1;
        visibility: visible;
      }
    }
  }

  .asset-card-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
  }

  .asset-card-title {
    font-weight: 500;
    color: var(--color-text-primary);
  }

  .asset-name {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 180px;
  }

  .platform-group {
    margin-bottom: 8px;
    padding: 6px 8px;
  }

  .platform-group-header {
    padding-bottom: 4px;
    margin-bottom: 4px;
  }

  .platform-title {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    color: var(--color-text-secondary);
    font-weight: 800;
    font-size: 12px;
  }

  .platform-icon {
    width: 18px;
    height: 18px;
  }

  .platform-group-assets {
    padding-left: 15px;
    margin-left: 3px;
    border-left: 2px solid var(--color-border);
  }
}

.empty-assets {
  border: 2px dashed var(--color-input-border);
  border-radius: 6px;
  padding: 56px 16px;
  text-align: center;
  cursor: pointer;
  transition:
    border-color 0.2s,
    background-color 0.25s,
    color 0.2s;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: var(--color-text-secondary);
  height: 100%;

  .icon {
    font-size: 42px;
    line-height: 1;
    margin-bottom: 14px;
    color: var(--color-disabled);
    transition: color 0.2s;
  }

  .title {
    font-size: 16px;
    font-weight: 600;
    margin-bottom: 6px;
  }

  .subtitle {
    font-size: 12px;
    opacity: 0.75;
  }
}

.empty-assets:hover:not(.is-disabled) {
  border-color: var(--color-primary);
  background: var(--color-disabled-background);
  color: var(--color-primary);

  .icon {
    color: var(--color-primary);
  }
}

.empty-assets.is-disabled {
  cursor: not-allowed;
  opacity: 0.55;
  background: var(--color-disabled-background);

  .disabled-tip {
    color: var(--color-disabled);
  }
}
</style>
