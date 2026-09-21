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
      <template #header>
        <div class="table-header">
        <span class="table-title">{{ $t('MachineAllocation') }}</span>
        <div class="table-actions">
          <el-checkbox v-model="showInactive" class="inactive-switch" @change="onToggleInactive">
            {{ $t('ShowInactive') }}
          </el-checkbox>
          <el-input
            v-model="search" size="small" clearable
            :placeholder="$t('Search')" prefix-icon="el-icon-search"
            style="width: 240px" @keyup.enter="onSearch" @clear="onSearch"
          />
          <el-button size="small" icon="el-icon-refresh" style="margin-left: 8px" @click="load" />
        </div>
      </div>
      </template>

      <el-table
        v-loading="loading" :data="results" size="medium"
        :row-class-name="rowClass"
      >
        <!-- 展开行: 机器明细 -->
        <el-table-column type="expand" width="40">
          <template v-slot:default="{ row }">
            <div class="expand-content">
              <div class="expand-title">{{ $t('AssignedUsers') }}: {{ row.users.map(u => u.name + '(' + u.pinyin + ')').join('、') }}</div>
              <el-table :data="row.assets" size="mini" class="expand-table" border>
                <el-table-column prop="name" :label="$tc('Asset')" min-width="160">
                  <template v-slot:default="{ row: asset }">
                    <span class="asset-name">{{ asset.name }}</span>
                    <span class="asset-addr">{{ asset.address }}</span>
                  </template>
                </el-table-column>
                <el-table-column prop="asset_nodes" :label="$t('AssetNode')" min-width="200" show-overflow-tooltip />
                <el-table-column :label="$t('K8sSchedule')" width="96" align="center">
                  <template v-slot:default="{ row: asset }">
                    <el-tag
                      v-if="asset.k8s_lock" size="mini"
                      :type="lockTagType(asset.k8s_lock)"
                    >
                      {{ lockLabel(asset.k8s_lock) }}
                    </el-tag>
                    <span v-else class="lock-none">-</span>
                  </template>
                </el-table-column>
                <el-table-column :label="$t('Action')" width="110" align="center">
                  <template v-slot:default="{ row: asset }">
                    <el-button
                      v-if="canRevoke && row.status === 'active'"
                      type="danger" size="mini" plain
                      @click="onClickRevokeAsset(row, asset)"
                    >
                      {{ $t('RevokeThisMachine') }}
                    </el-button>
                  </template>
                </el-table-column>
              </el-table>
            </div>
          </template>
        </el-table-column>

        <!-- 工单号 -->
        <el-table-column :label="$t('PermissionID')" min-width="180">
          <template v-slot:default="{ row }">
            <div class="ticket-serial">{{ row.ticket_serial || row.permission_id.slice(0, 8) }}</div>
            <div class="perm-name" :title="row.permission_name">{{ (row.permission_name || '').slice(0, 30) }}</div>
          </template>
        </el-table-column>

        <!-- 用户 -->
        <el-table-column :label="$t('User')" min-width="120">
          <template v-slot:default="{ row }">
            <div v-for="u in row.users" :key="u.user_id" class="user-line">
              <span class="user-name">{{ u.name }}</span>
              <code class="user-pinyin">{{ u.pinyin }}</code>
            </div>
          </template>
        </el-table-column>

        <!-- 审批人 -->
        <el-table-column :label="$t('Approver2')" width="140" show-overflow-tooltip>
          <template v-slot:default="{ row }">{{ row.approvers || '-' }}</template>
        </el-table-column>

        <!-- 机器数 -->
        <el-table-column :label="$tc('Asset')" width="70" align="center">
          <template v-slot:default="{ row }">
            <el-tag size="small" type="info">{{ row.asset_count }}</el-tag>
          </template>
        </el-table-column>

        <!-- 到期时间 -->
        <el-table-column :label="$t('ExpireDateTime')" width="140">
          <template v-slot:default="{ row }">
            {{ formatTime(row.date_expired) || $t('Permanent') }}
          </template>
        </el-table-column>

        <!-- 状态 -->
        <el-table-column :label="$t('ExpireStatus')" width="110" align="center">
          <template v-slot:default="{ row }">
            <el-tag v-if="row.status === 'revoked'" type="info" size="small">{{ $t('Revoked') }}</el-tag>
            <el-tag v-else-if="row.status === 'expired'" type="info" size="small">{{ $t('AlreadyExpired') }}</el-tag>
            <span v-else :class="dayClass(row.days_left)">{{ expireText(row.days_left) }}</span>
          </template>
        </el-table-column>

        <!-- 操作 -->
        <el-table-column :label="$t('Action')" width="90" align="center">
          <template v-slot:default="{ row }">
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
        v-model:current-page="page"
        :page-size="pageSize"
        @current-change="load"
      />
    </el-card>

    <!-- 吊销确认 -->
    <el-dialog
      :title="$t('RevokeAllocation')" v-model="revoke.visible"
      width="480px" :close-on-click-modal="false"
    >
      <div class="revoke-body">
        <template v-if="revoke.mode === 'asset'">
          <div class="revoke-line">
            {{ $t('User') }}: <b>{{ revoke.userName }}</b>
          </div>
          <div class="revoke-line">
            {{ $tc('Asset') }}: <b>{{ revoke.assetName }}</b>
            <span class="revoke-sub">({{ revoke.assetAddress }})</span>
          </div>
        </template>
        <template v-else>
          <div class="revoke-line">
            {{ $t('PermissionID') }}: <b>{{ revoke.ticketSerial }}</b>
          </div>
          <div class="revoke-line">
            {{ $t('User') }}: <b>{{ revoke.userName }}</b>
          </div>
          <div class="revoke-line">
            {{ $tc('Asset') }}: <b>{{ revoke.assetCount }}</b> {{ $tc('Asset') }}
          </div>
        </template>
        <div class="revoke-line revoke-tip">{{ $t('RevokeConfirmTip') }}</div>
        <div class="revoke-line revoke-tip">{{ $t('RevokeNote') }}</div>
      </div>
      <template #footer>
        <div>
        <el-button @click="revoke.visible = false">{{ $t('Cancel') }}</el-button>
        <el-button
          v-if="revoke.mode === 'asset'"
          type="danger" :loading="revoke.loading"
          @click="doRevoke('asset')"
        >
          {{ $t('RevokeThisMachine') }}
        </el-button>
        <el-button
          v-else
          type="danger" :loading="revoke.loading"
          @click="doRevoke('permission')"
        >
          {{ $t('RevokeWholePermission').replace('{}', revoke.assetCount || 'N') }}
        </el-button>
      </div>
      </template>
    </el-dialog>
  </div>
</template>

<script>
// fork 定制: 机器分配总览(按工单分组, 展开行显示机器明细)
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
        mode: 'permission',  // 'permission' | 'asset'
        permissionId: '',
        userId: '',
        userName: '',
        ticketSerial: '',
        assetCount: 0,
        assetId: '',
        assetName: '',
        assetAddress: ''
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
    formatTime(value) {
      if (!value) return ''
      return String(value).replace('T', ' ').slice(0, 16)
    },
    // K8s 调度锁状态(kite_lock): locked/released/pending/failed/not_found
    lockTagType(state) {
      const map = {
        locked: 'warning',
        released: 'success',
        pending: 'info',
        not_found: 'info',
        failed: 'danger'
      }
      return map[state] || 'info'
    },
    lockLabel(state) {
      const map = {
        locked: 'K8sLockLocked',
        released: 'K8sLockReleased',
        pending: 'K8sLockPending',
        not_found: 'K8sLockNotFound',
        failed: 'K8sLockFailed'
      }
      return this.$t(map[state] || 'K8sLockNone')
    },
    expireText(days) {
      if (days === null) return '-'
      if (days < 0) return this.$t('AlreadyExpired')
      return `${this.$t('DaysLeft')} ${days} ${this.$tc('Day')}`
    },
    dayClass(days) {
      if (days === null) return ''
      if (days <= 7) return 'text-danger'
      if (days <= 30) return 'text-warning'
      return ''
    },
    // 吊销整个授权(父行按钮)
    onClickRevoke(row) {
      const user = row.users[0] || {}
      this.revoke = {
        ...this.revoke,
        visible: true,
        mode: 'permission',
        permissionId: row.permission_id,
        userId: user.user_id || '',
        userName: row.users.map(u => u.name).join('、'),
        ticketSerial: row.ticket_serial,
        assetCount: row.asset_count
      }
    },
    // 仅吊销单台机器(展开行按钮)
    onClickRevokeAsset(row, asset) {
      const user = row.users[0] || {}
      this.revoke = {
        ...this.revoke,
        visible: true,
        mode: 'asset',
        permissionId: row.permission_id,
        userId: user.user_id || '',
        userName: user.name || '',
        assetId: asset.asset_id,
        assetName: asset.name,
        assetAddress: asset.address
      }
    },
    doRevoke(scope) {
      const body = {
        scope: scope,
        user_id: this.revoke.userId
      }
      if (scope === 'asset') {
        body.asset_id = this.revoke.assetId
      } else {
        body.permission_id = this.revoke.permissionId
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
  .stat-row { margin-bottom: 16px; }

  .stat-card {
    text-align: center;
    .stat-num {
      font-size: 26px; font-weight: 700; line-height: 1.4;
      &.warn { color: #ff7d00; }
    }
    .stat-name {
      margin-top: 2px; font-size: 12px;
      color: var(--color-text-secondary, #86909c);
    }
  }

  .table-header {
    display: flex; align-items: center; justify-content: space-between;
    .table-title { font-size: 15px; font-weight: 600; }
    .table-actions {
      display: flex; align-items: center;
      .inactive-switch { margin-right: 16px; }
    }
  }

  .ticket-serial { font-weight: 600; font-size: 14px; }
  .perm-name {
    font-size: 11px;
    color: var(--color-text-secondary, #86909c);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 180px;
  }

  .user-line {
    display: flex; align-items: center; gap: 6px; line-height: 1.8;
    .user-name { font-weight: 500; }
    .user-pinyin {
      font-family: Menlo, Consolas, monospace; font-size: 12px;
      color: var(--color-text-secondary, #86909c);
    }
  }

  .expand-content {
    padding: 8px 48px;
    .expand-title {
      margin-bottom: 8px; font-size: 13px; font-weight: 500;
    }
    .expand-table {
      .asset-name { font-weight: 600; margin-right: 8px; }
      .asset-addr { font-size: 12px; color: var(--color-text-secondary, #86909c); }
    }
  }

  :deep(.row-inactive) { opacity: 0.55; }

  .text-warning { color: #ff7d00; font-weight: 600; }
  .text-danger { color: #f53f3f; font-weight: 600; }

  .pager { margin-top: 16px; text-align: right; }

  .revoke-body {
    .revoke-line { margin-bottom: 8px; line-height: 1.8; }
    .revoke-sub { font-size: 12px; color: var(--color-text-secondary, #86909c); }
    .revoke-tip { font-size: 12px; color: var(--color-text-secondary, #86909c); }
  }
}
</style>
