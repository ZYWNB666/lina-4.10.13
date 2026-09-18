<template>
  <IBox>
    <GenericCreateUpdateForm v-bind="config" @submit-success="submitSuccess" />
  </IBox>
</template>

<script>
import { GenericCreateUpdateForm } from '@/layout/components'
import { IBox } from '@/components'

export default {
  name: 'Ticket',
  components: {
    GenericCreateUpdateForm,
    IBox
  },
  props: {
    value: {
      type: Boolean,
      required: false
    }
  },
  data() {
    return {
      visible: false,
      config: {
        fields: [
          [this.$t('Basic'), ['TICKETS_ENABLED', 'TICKETS_DIRECT_APPROVE']],
          [
            this.$t('AssetPermission'),
            ['TICKET_AUTHORIZE_DEFAULT_TIME', 'TICKET_AUTHORIZE_DEFAULT_TIME_UNIT']
          ]
        ],
        fieldsMeta: {},
        successUrl: { name: 'Settings', params: { activeMenu: 'Basic' } },
        url: '/api/v1/settings/setting/?category=ticket',
        hasReset: false,
        submitMethod() {
          return 'patch'
        }
      }
    }
  },
  methods: {
    submitSuccess(res) {
      this.$store.dispatch('settings/getPublicSettings')
      this.$emit('input', !!res.TICKETS_ENABLED)
      this.visible = false
    }
  }
}
</script>

<style scoped></style>
