<template>
  <div class="app-container machine-allocation">
    <el-row :gutter="16" class="stat-row">
      <el-col :xs="12" :sm="6">
        <el-card shadow="never" class="stat-card">
          <div class="stat-num">{{ stats.machines }}</div>
          <div class="stat-name">{{ $t('AllocatedMachines') }}</div>
        </el-card>
      </el-col>
      <el-col :xs="12" :sm="6">
        <el-card shadow="never" class="stat-card">
          <div class="stat-num">{{ stats.users }}</div>
          <div class="stat-name">{{ $t('GrantCount') }}</div>
        </el-card>
      </el-col>
      <el-col :xs="12" :sm="6">
        <el-card shadow="never" class="stat-card">
          <div class="stat-num warn">{{ stats.expiring_7 }}</div>
          <div class="stat-name">{{ $t('Expiring7') }}</div>
        </el-card>
      </el-col>
      <el-col :xs="12" :sm="6">
        <el-card shadow="never" class="stat-card">
          <div class="stat-num warn">{{ stats.expiring_30 }}</div>
          <div class="stat-name">{{ $t('Expiring30') }}</div>
        </el-card>
      </el-col>
    </el-row>

    <el-card shadow="never" class="table-card">
      <div slot="header" class="table-header">
        <span class="table-title">{{ $t('MachineAllocation') }}</span>
        <div class="table-actions">
          <el-checkbox v-model="showInactive" class="inactive-switch" @change="onToggleInactive">
            {{ $t('ShowInactive') }}
          </el-checkbox>
          <el-input
            v-model="search" size="small" clearable
            :placeholder="$t('Search')" prefix-icon="el-icon-search"
            style="width: 240px" @keyup.enter.native="onSearch" @clear="onSearch"
          />
          <el-button size="small" icon="el-icon-refresh" style="margin-left: 8px" @click="load" />
        </div>
      </div>

      <el-table
        v-loading="loading" :data="results" size="medium"
        :row-class-name="rowClass"
      >
        <el-table-column :label="$tc('Asset')" min-width="220">
          <template slot-scope="{ row }">
            <div class="asset-name">{{ row.asset_name }}</div>
            <div class="asset-addr">{{ row.asset_address }}</div>
            <div class="asset-node" :title="row.asset_nodes">{{ row.asset_nodes }}</div>
          </template>
        </el-table-column>

        <el-table-column :label="$t('User')" width="110">
          <template slot-scope="{ row }">{{ row.name }}</template>
        </el-table-column>

        <el-table-column :label="$t('HostUsername')" width="130">
          <template slot-scope="{ row }">
            <code class="host-username">{{ row.pinyin }}</code>
          </template>
        </el-table-column>

        <el-table-column :label="$t('Approver2')" width="150" show-overflow-tooltip>
          <template slot-scope="{ row }">{{ row.approvers || '-' }}</template>
        </el-table-column>

        <el-table-column :label="$t('PermissionID')" width="130">
          <template slot-scope="{ row }">
            <el-tooltip :content="row.permission_id" placement="top">
              <code class="perm-id">{{ shortPermId(row.permission_id) }}</code>
            </el-tooltip>
          </template>
        </el-table-column>

        <el-table-column :label="$t('ExpireDateTime')" width="150">
          <template slot-scope="{ row }">
            {{ formatTime(row.date_expired) || $t('Permanent') }}
          </template>
        </el-table-column>

        <el-table-column :label="$t('ExpireStatus')" width="120" align="center">
          <template slot-scope="{ row }">
            <el-tag v-if="row.status === 'revoked'" type="info" size="small">{{ $t('Revoked') }}</el-tag>
            <el-tag v-else-if="row.status === 'expired'" type="info" size="small">{{ $t('AlreadyExpired') }}</el-tag>
            <span v-else :class="dayClass(row.days_left)">{{ expireText(row.days_left) }}</span>
          </template>
        </el-table-column>

        <el-table-column :label="$t('Action')" width="90" align="center">
          <template slot-scope="{ row }">
            <el-button
              v-if="canRevoke && row.status === 'active'"
              type="danger" size="mini" plain
              @click="onClickRevoke(row)"
            >
              {{ $t('Revoke') }}
            </el-button>
          </template>
        </el-table-column>
      </el-table>

      <el-pagination
        class="pager"
        background
        layout="total, prev, pager, next"
        :total="count"
        :current-page.sync="page"
        :page-size="pageSize"
        @current-change="load"
      />
    </el-card>

    <!-- 吊销确认 (fork 定制) -->
    <el-dialog
      :title="$t('RevokeAllocation')" :visible.sync="revoke.visible"
      width="480px" :close-on-click-modal="false"
    >
      <div class="revoke-body">
        <div class="revoke-line">
          {{ $t('User') }}: <b>{{ revoke.entry.name }}</b>
          <span class="revoke-sub">({{ revoke.entry.pinyin }})</span>
        </div>
        <div class="revoke-line">
          {{ $tc('Asset') }}: <b>{{ revoke.entry.asset_name }}</b>
          <span class="revoke-sub">({{ revoke.entry.asset_address }})</span>
        </div>
        <div class="revoke-line revoke-tip">{{ $t('RevokeConfirmTip') }}</div>
        <div class="revoke-line revoke-tip">{{ $t('RevokeNote') }}</div>
      </div>
      <div slot="footer">
        <el-button @click="revoke.visible = false">{{ $t('Cancel') }}</el-button>
        <el-button :loading="revoke.loading" @click="doRevoke('asset')">
          {{ $t('RevokeThisMachine') }}
        </el-button>
        <el-button type="danger" :loading="revoke.loading" @click="doRevoke('permission')">
          {{ $t('RevokeWholePermission').replace('{}', revoke.entry.permission_assets || 'N') }}
        </el-button>
      </div>
    </el-dialog>
  </div>
</template>

<script>
// fork 定制: 机器分配总览(扁平记录, 默认隐藏已到期/已吊销, 可勾选查看)
export default {
  name: 'MachineAllocation',
  data() {
    return {
      loading: false,
      results: [],
      stats: {},
      count: 0,
      page: 1,
      pageSize: 20,
      search: '',
      showInactive: false,
      revoke: {
        visible: false,
        loading: false,
        entry: {}
      }
    }
  },
  computed: {
    canRevoke() {
      const perms = this.$store.getters.currentOrgPerms
      return perms && perms.includes('perms.delete_assetpermission')
    }
  },
  mounted() {
    this.load()
  },
  methods: {
    async load() {
      this.loading = true
      try {
        const params = [
          `page=${this.page}`,
          `page_size=${this.pageSize}`,
          `search=${encodeURIComponent(this.search)}`
        ]
        if (this.showInactive) {
          params.push('show_inactive=1')
        }
        const data = await this.$axios.get('/api/v1/xpack/feishu-approval/allocation/?' + params.join('&'))
        this.results = data.results || []
        this.count = data.count || 0
        this.stats = data.stats || {}
      } catch (e) {
        // 拦截器已提示
      } finally {
        this.loading = false
      }
    },
    onSearch() {
      this.page = 1
      this.load()
    },
    onToggleInactive() {
      this.page = 1
      this.load()
    },
    rowClass({ row }) {
      return row.status === 'active' ? '' : 'row-inactive'
    },
    shortPermId(id) {
      return (id || '').slice(0, 8) + '…'
    },
    formatTime(value) {
      if (!value) {
        return ''
      }
      return String(value).replace('T', ' ').slice(0, 16)
    },
    expireText(days) {
      if (days === null) {
        return '-'
      }
      if (days < 0) {
        return this.$t('AlreadyExpired')
      }
      return `${this.$t('DaysLeft')} ${days} ${this.$tc('Day')}`
    },
    dayClass(days) {
      if (days === null) {
        return ''
      }
      if (days <= 7) {
        return 'text-danger'
      }
      if (days <= 30) {
        return 'text-warning'
      }
      return ''
    },
    onClickRevoke(row) {
      this.revoke.entry = row
      this.revoke.visible = true
    },
    doRevoke(scope) {
      const entry = this.revoke.entry
      const body = { scope: scope, user_id: entry.user_id }
      if (scope === 'asset') {
        body.asset_id = entry.asset_id
      } else {
        body.permission_id = entry.permission_id
      }
      this.revoke.loading = true
      this.$axios.post(
        '/api/v1/xpack/feishu-approval/allocation/revoke/', body, { disableFlashErrorMsg: true }
      ).then(data => {
        this.$message.success(this.$t('Revoked'))
        if (data.warning) {
          this.$message.warning(this.$t('NodeGrantWarning'))
        }
        this.revoke.visible = false
        this.load()
      }).catch(error => {
        const resp = error.response
        const msg = resp ? (resp.data.error || Object.values(resp.data)[0]) : this.$t('ServerError')
        this.$message.error(typeof msg === 'string' ? msg : JSON.stringify(msg))
      }).finally(() => {
        this.revoke.loading = false
      })
    }
  }
}
</script>

<style lang="scss" scoped>
.machine-allocation {
  .stat-row {
    margin-bottom: 16px;
  }

  .stat-card {
    text-align: center;

    .stat-num {
      font-size: 26px;
      font-weight: 700;
      line-height: 1.4;

      &.warn {
        color: #ff7d00;
      }
    }

    .stat-name {
      margin-top: 2px;
      font-size: 12px;
      color: var(--color-text-secondary, #86909c);
    }
  }

  .table-header {
    display: flex;
    align-items: center;
    justify-content: space-between;

    .table-title {
      font-size: 15px;
      font-weight: 600;
    }

    .table-actions {
      display: flex;
      align-items: center;

      .inactive-switch {
        margin-right: 16px;
      }
    }
  }

  .asset-name {
    font-weight: 600;
  }

  .asset-addr {
    font-size: 12px;
    color: var(--color-text-secondary, #86909c);
  }

  .asset-node {
    font-size: 12px;
    color: var(--color-text-secondary, #86909c);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 220px;
  }

  .host-username,
  .perm-id {
    font-family: Menlo, Consolas, monospace;
    font-size: 12px;
    color: var(--color-text-primary, #4e5960);
  }

  ::v-deep .row-inactive {
    opacity: 0.55;
  }

  .text-warning {
    color: #ff7d00;
    font-weight: 600;
  }

  .text-danger {
    color: #f53f3f;
    font-weight: 600;
  }

  .pager {
    margin-top: 16px;
    text-align: right;
  }

  .revoke-body {
    .revoke-line {
      margin-bottom: 8px;
      line-height: 1.8;
    }

    .revoke-sub {
      font-size: 12px;
      color: var(--color-text-secondary, #86909c);
    }

    .revoke-tip {
      font-size: 12px;
      color: var(--color-text-secondary, #86909c);
    }
  }
}
</style>
