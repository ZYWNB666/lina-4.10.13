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
          <el-input
            v-model="search" size="small" clearable
            :placeholder="$t('Search')" prefix-icon="el-icon-search"
            style="width: 260px" @keyup.enter.native="onSearch" @clear="onSearch"
          />
          <el-button size="small" icon="el-icon-refresh" style="margin-left: 8px" @click="load" />
        </div>
      </div>

      <el-table v-loading="loading" :data="results" size="medium">
        <el-table-column :label="$tc('Asset')" min-width="170">
          <template slot-scope="{ $index }">
            <div class="asset-name">{{ results[$index].name }}</div>
            <div class="asset-addr">{{ results[$index].address }}</div>
          </template>
        </el-table-column>
        <el-table-column :label="$t('AssignedUsers')" min-width="420">
          <template slot-scope="{ $index }">
            <span
              v-for="u in results[$index].users"
              :key="u.user_id"
              class="user-chip"
              :class="chipClass(u.days_left)"
            >
              {{ u.name }}
              <span class="chip-py">{{ u.pinyin }}</span>
              <span class="chip-serial">{{ u.ticket_serial }}</span>
              <span class="chip-date">{{ (u.date_expired || '').slice(0, 10) || $t('Permanent') }}</span>
            </span>
          </template>
        </el-table-column>
        <el-table-column :label="$t('ExpireStatus')" width="130" align="center">
          <template slot-scope="{ $index }">
            <span :class="dayClass(minDaysLeft(results[$index]))">
              {{ expireText(minDaysLeft(results[$index])) }}
            </span>
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
  </div>
</template>

<script>
// fork 定制: 机器分配总览(仅展示工单审批分配且未过期的授权)
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
      search: ''
    }
  },
  mounted() {
    this.load()
  },
  methods: {
    async load() {
      this.loading = true
      try {
        const params = `?page=${this.page}&page_size=${this.pageSize}&search=${encodeURIComponent(this.search)}`
        const data = await this.$axios.get('/api/v1/xpack/feishu-approval/allocation/' + params)
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
    minDaysLeft(row) {
      if (!row.users || row.users.length === 0) {
        return null
      }
      return Math.min(...row.users.map(u => u.days_left === null ? 9999 : u.days_left))
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
    chipClass(days) {
      if (days === null) {
        return ''
      }
      if (days <= 7) {
        return 'chip-danger'
      }
      if (days <= 30) {
        return 'chip-warning'
      }
      return ''
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
  }

  .asset-name {
    font-weight: 600;
  }

  .asset-addr {
    font-size: 12px;
    color: var(--color-text-secondary, #86909c);
  }

  .user-chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin: 2px 6px 2px 0;
    padding: 3px 10px;
    background: var(--color-primary-light-9, #f2f3f5);
    border: 1px solid var(--color-border, #e5e6eb);
    border-radius: 14px;
    font-size: 12px;
    color: var(--color-text-primary, #4e5969);

    .chip-py {
      color: var(--color-text-secondary, #86909c);
    }

    .chip-serial {
      color: var(--color-text-secondary, #86909c);
    }

    .chip-date {
      color: var(--color-text-secondary, #86909c);
    }

    &.chip-warning {
      border-color: #ff7d00;
      color: #ff7d00;
    }

    &.chip-danger {
      border-color: #f53f3f;
      color: #f53f3f;
    }
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
}
</style>
