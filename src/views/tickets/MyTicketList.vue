<template>
  <BaseTicketList v-bind="$data" :url="url" />
</template>

<script>
import { mapGetters } from 'vuex'
import BaseTicketList from './BaseTicketList'

export default {
  name: 'MyTicketList',
  components: {
    BaseTicketList
  },
  data() {
    return {
      extraTicketAction: {
        // fork 定制: 旧「申请资产授权」工单表单已下线, 入口直达机器申请
        moreCreates: { has: false },
        extraActions: [
          {
            name: 'MachineApply',
            title: this.$t('MachineApply'),
            icon: 'plus',
            type: 'primary',
            callback: () => {
              this.$router.push({ name: 'MachineApply' })
            }
          }
        ]
      }
    }
  },
  computed: {
    url() {
      return `/api/v1/tickets/tickets/?applicant=${this.currentUser.id}&state=pending`
    },
    ...mapGetters(['currentUser'])
  }
}
</script>
