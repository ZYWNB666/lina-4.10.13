<template>
  <Dialog
    :visible="visible"
    :title="$t('JobSelectDirectories')"
    width="680px"
    :close-on-click-modal="false"
    @update:visible="$emit('update:visible', $event)"
    @cancel="$emit('update:visible', false)"
    @confirm="confirm"
  >
    <p class="directory-help">{{ $t('JobDirectoryHelp') }}</p>
    <div class="directory-tree">
      <NodeAssetTree :setting="treeSetting">
        <template #node-actions="{ data }">
          <el-checkbox
            v-if="isDirectory(data)"
            :aria-label="$t('JobSelectDirectory', { name: data.name })"
            :model-value="isSelected(data)"
            @click.stop
            @change="toggleDirectory(data, $event)"
          />
        </template>
      </NodeAssetTree>
    </div>
    <div class="directory-selection">
      <span>{{ $t('JobDirectoryCount', { count: selected.length }) }}</span>
      <el-tag v-for="node in selected" :key="node.id" closable @close="remove(node.id)">
        {{ node.name }}
      </el-tag>
    </div>
  </Dialog>
</template>

<script>
import Dialog from '@/components/Dialog'
import NodeAssetTree from '@/components/Tree/NodeAssetTree/index.vue'
import { createUserAuthorizationTreeDataSource } from '@/components/Apps/GrantedAssets/treeDataSource'

export default {
  components: { Dialog, NodeAssetTree },
  props: {
    visible: Boolean,
    value: { type: Array, default: () => [] }
  },
  emits: ['update:visible', 'confirm'],
  data() {
    return {
      selected: this.value.map((node) => ({ ...node })),
      treeSetting: {
        dataSource: createUserAuthorizationTreeDataSource(this.$axios, 'self'),
        settingsCacheKey: 'job-directory-select',
        childrenPagination: true,
        countResource: 'asset',
        defaultMetricMode: 'asset_all',
        metricModes: ['asset_all'],
        fillHeight: true,
        notShowBuiltinTree: true,
        readOnly: true,
        selectSyncToRoute: false,
        showAssets: false,
        showSearch: false,
        showMetrics: false,
        showNodeActions: false,
        showMenu: false,
        hasRightMenu: false,
        showRefresh: true,
        showCollapse: true,
        showAssetScope: false,
        showAssetOrder: false,
        showPermissionScope: false,
        edit: { drag: { isMove: false } }
      }
    }
  },
  methods: {
    isDirectory(node) {
      const id = node?.meta?.data?.id
      return (
        node?.meta?.type === 'node' &&
        (id === 'ungrouped' || /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(id || ''))
      )
    },
    isSelected(node) {
      return this.selected.some((item) => item.id === node.meta.data.id)
    },
    toggleDirectory(node, checked) {
      if (!this.isDirectory(node)) return
      const id = node.meta.data.id
      this.remove(id)
      if (checked) this.selected.push({ id, name: node.name })
    },
    remove(id) {
      this.selected = this.selected.filter((node) => node.id !== id)
    },
    confirm() {
      this.$emit('confirm', this.selected)
      this.$emit('update:visible', false)
    }
  }
}
</script>

<style scoped lang="scss">
.directory-help {
  margin: 0 0 12px;
  line-height: 1.6;
  color: var(--color-text-secondary);
}
.directory-tree {
  height: min(420px, 50vh);
  border: 1px solid var(--color-border);
  border-radius: 6px;
  padding: 8px;

  :deep(.el-checkbox) {
    margin: 0 8px 0 auto;
  }
}
.directory-selection {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-top: 12px;
  max-height: 100px;
  overflow: auto;
}
</style>
