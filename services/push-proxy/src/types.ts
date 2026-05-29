export interface RegisterRequest {
  platform: "ios" | "android"
  pushToken: string
  apnsEnvironment?: "production" | "sandbox"
  contentState?: ContentState
  intervalSeconds?: number
  ttlSeconds?: number
}

export interface ContentState {
  phase?: string
  elapsedSeconds?: number
  toolCallCount?: number
  activeThreadCount?: number
  serverId?: string
  threadId?: string
}

export interface Env {
  PUSH_REGISTRATION: DurableObjectNamespace
  RATE_LIMITER: DurableObjectNamespace
  PUSH_KV: KVNamespace
  APNS_TEAM_ID: string
  APNS_KEY_ID: string
  APNS_PRIVATE_KEY: string
  FCM_PROJECT_ID: string
  FCM_CLIENT_EMAIL: string
  FCM_PRIVATE_KEY: string
}
